-- Portfolio 3: integrity check. Run before and after each stress test.
SELECT
  (SELECT sum(balance) FROM accounts) AS total_money_in_system,

  (SELECT count(*) FROM (
     SELECT transaction_id
     FROM ledger_entries
     GROUP BY transaction_id
     HAVING sum(CASE WHEN direction = 'DEBIT' THEN amount ELSE -amount END) <> 0
   ) x) AS unbalanced_transactions,

  (SELECT count(*) FROM (
     SELECT a.account_id
     FROM accounts a
     JOIN LATERAL (
       SELECT balance_after FROM ledger_entries l
       WHERE l.account_id = a.account_id
       ORDER BY l.created_at DESC, l.entry_id DESC LIMIT 1
     ) last ON true
     WHERE a.balance <> last.balance_after
   ) y) AS mismatched_accounts,

  (SELECT count(*) FROM transactions WHERE status = 'PENDING') AS stuck_pending_transactions;