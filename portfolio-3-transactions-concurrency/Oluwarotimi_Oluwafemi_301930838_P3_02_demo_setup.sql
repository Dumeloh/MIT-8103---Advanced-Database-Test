-- Portfolio 3: demo wallets for the experiments.
-- Safe to re-run: it resets both wallets to 500.00 each time.

INSERT INTO customers (first_name, last_name, email, phone, customer_type)
VALUES ('Demo', 'Alice', 'demo.alice@carbon.test', '08000000001', 'INDIVIDUAL'),
       ('Demo', 'Bob',   'demo.bob@carbon.test',   '08000000002', 'INDIVIDUAL')
ON CONFLICT (email) DO NOTHING;

INSERT INTO accounts (customer_id, account_number, balance)
SELECT customer_id, '9000000001', 500.00 FROM customers WHERE email = 'demo.alice@carbon.test'
ON CONFLICT (account_number) DO UPDATE SET balance = 500.00, status = 'ACTIVE';

INSERT INTO accounts (customer_id, account_number, balance)
SELECT customer_id, '9000000002', 500.00 FROM customers WHERE email = 'demo.bob@carbon.test'
ON CONFLICT (account_number) DO UPDATE SET balance = 500.00, status = 'ACTIVE';

SELECT account_number, balance FROM accounts
WHERE account_number IN ('9000000001', '9000000002');