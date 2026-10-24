-- Portfolio 3: Carbon transfer functions
-- transfer_funds           = the correct version (idempotent, ordered locks)
-- transfer_funds_unordered = deliberately flawed copy, used ONLY to show deadlocks

CREATE OR REPLACE FUNCTION transfer_funds(
    p_from_account    text,
    p_to_account      text,
    p_amount          numeric,
    p_idempotency_key text
) RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_txn         bigint;
    v_from_id     bigint;
    v_to_id       bigint;
    v_first       bigint;
    v_second      bigint;
    v_from_bal    numeric(19,4);
    v_to_bal      numeric(19,4);
    v_from_status text;
    v_to_status   text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    IF p_from_account = p_to_account THEN
        RAISE EXCEPTION 'Cannot transfer to the same account';
    END IF;

    -- 1. IDEMPOTENCY FIRST: register the request. If the key already exists,
    --    return the original transaction and do nothing else.
    INSERT INTO transactions (idempotency_key, txn_type, status, amount, reference)
    VALUES (p_idempotency_key, 'TRANSFER', 'PENDING', p_amount,
            p_from_account || ' -> ' || p_to_account)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING transaction_id INTO v_txn;

    IF v_txn IS NULL THEN
        SELECT transaction_id INTO v_txn
        FROM transactions WHERE idempotency_key = p_idempotency_key;
        RETURN v_txn;
    END IF;

    -- 2. RESOLVE ACCOUNT IDS (no locks yet)
    SELECT account_id INTO v_from_id FROM accounts WHERE account_number = p_from_account;
    IF v_from_id IS NULL THEN
        RAISE EXCEPTION 'Sender account % not found', p_from_account;
    END IF;
    SELECT account_id INTO v_to_id FROM accounts WHERE account_number = p_to_account;
    IF v_to_id IS NULL THEN
        RAISE EXCEPTION 'Receiver account % not found', p_to_account;
    END IF;

    -- 3. LOCK IN A FIXED ORDER: lowest account_id first, so two opposite
    --    transfers can never wait on each other in a circle.
    v_first  := LEAST(v_from_id, v_to_id);
    v_second := GREATEST(v_from_id, v_to_id);
    PERFORM 1 FROM accounts WHERE account_id = v_first  FOR UPDATE;
    PERFORM 1 FROM accounts WHERE account_id = v_second FOR UPDATE;

    -- 4. READ BALANCES AFTER LOCKING (reading before locking = lost update)
    SELECT balance, status INTO v_from_bal, v_from_status
    FROM accounts WHERE account_id = v_from_id;
    SELECT balance, status INTO v_to_bal, v_to_status
    FROM accounts WHERE account_id = v_to_id;

    IF v_from_status <> 'ACTIVE' OR v_to_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Both accounts must be ACTIVE';
    END IF;
    IF v_from_bal < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds in account %', p_from_account;
    END IF;

    -- 5. APPLY: two balance updates + DEBIT and CREDIT ledger lines (double entry)
    UPDATE accounts SET balance = balance - p_amount WHERE account_id = v_from_id;
    UPDATE accounts SET balance = balance + p_amount WHERE account_id = v_to_id;

    INSERT INTO ledger_entries (transaction_id, account_id, direction, amount, balance_after, created_at)
    VALUES (v_txn, v_from_id, 'DEBIT',  p_amount, v_from_bal - p_amount, clock_timestamp()),
           (v_txn, v_to_id,   'CREDIT', p_amount, v_to_bal   + p_amount, clock_timestamp());

    UPDATE transactions
    SET status = 'COMPLETED', completed_at = clock_timestamp()
    WHERE transaction_id = v_txn;

    RETURN v_txn;
END;
$$;


-- FLAWED COPY: locks the SENDER first, then the RECEIVER (no ordering).
-- The short pg_sleep widens the window so deadlocks show up reliably.
CREATE OR REPLACE FUNCTION transfer_funds_unordered(
    p_from_account    text,
    p_to_account      text,
    p_amount          numeric,
    p_idempotency_key text
) RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_txn         bigint;
    v_from_id     bigint;
    v_to_id       bigint;
    v_from_bal    numeric(19,4);
    v_to_bal      numeric(19,4);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    IF p_from_account = p_to_account THEN
        RAISE EXCEPTION 'Cannot transfer to the same account';
    END IF;

    INSERT INTO transactions (idempotency_key, txn_type, status, amount, reference)
    VALUES (p_idempotency_key, 'TRANSFER', 'PENDING', p_amount,
            p_from_account || ' -> ' || p_to_account)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING transaction_id INTO v_txn;

    IF v_txn IS NULL THEN
        SELECT transaction_id INTO v_txn
        FROM transactions WHERE idempotency_key = p_idempotency_key;
        RETURN v_txn;
    END IF;

    SELECT account_id INTO v_from_id FROM accounts WHERE account_number = p_from_account;
    IF v_from_id IS NULL THEN RAISE EXCEPTION 'Sender account % not found', p_from_account; END IF;
    SELECT account_id INTO v_to_id FROM accounts WHERE account_number = p_to_account;
    IF v_to_id IS NULL THEN RAISE EXCEPTION 'Receiver account % not found', p_to_account; END IF;

    -- THE FLAW: sender first, receiver second, whatever the ids are
    SELECT balance INTO v_from_bal FROM accounts WHERE account_id = v_from_id FOR UPDATE;
    PERFORM pg_sleep(0.005);
    SELECT balance INTO v_to_bal   FROM accounts WHERE account_id = v_to_id   FOR UPDATE;

    IF v_from_bal < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds in account %', p_from_account;
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE account_id = v_from_id;
    UPDATE accounts SET balance = balance + p_amount WHERE account_id = v_to_id;

    INSERT INTO ledger_entries (transaction_id, account_id, direction, amount, balance_after, created_at)
    VALUES (v_txn, v_from_id, 'DEBIT',  p_amount, v_from_bal - p_amount, clock_timestamp()),
           (v_txn, v_to_id,   'CREDIT', p_amount, v_to_bal   + p_amount, clock_timestamp());

    UPDATE transactions
    SET status = 'COMPLETED', completed_at = clock_timestamp()
    WHERE transaction_id = v_txn;

    RETURN v_txn;
END;
$$;