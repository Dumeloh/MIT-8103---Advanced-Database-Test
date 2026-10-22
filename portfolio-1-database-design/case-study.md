# Case Study: CarbonPay — A Simulated Carbon Fintech Platform

Course: MIT 8103 – Advanced Database Systems

Module: Portfolio 1 – Database Design and Modelling

Target System: `carbonpay_db` | Database: PostgreSQL 16

Since you have already created your PostgreSQL tables, this new case study will use your existing schema as its foundation. It follows the structure of your NairaPay reference case study, but adapts the business context, workflows, actors, security requirements, and database challenges to a simulated Carbon fintech platform.

Important: CarbonPay in this case study is a fictionalized learning scenario inspired by digital lending and financial services. It is not a description of Carbon's actual internal systems or database architecture.

## 1. Executive Summary and Industry Context

### 1.1 The Nigerian Digital Lending and Fintech Landscape

Nigeria's fintech industry has expanded access to digital payments, mobile wallets, consumer lending, and other financial services. Customers increasingly expect to open accounts, verify their identities, receive funds, repay obligations, and monitor transactions through digital platforms.

A Carbon-inspired fintech platform must manage more than ordinary banking transactions. Its database must support reliable money movement, identity verification, customer account management, fraud detection, and accurate financial records.

The platform faces several important technical challenges:

- Transaction reliability: Mobile networks and external payment gateways can fail during deposits, transfers, withdrawals, and repayments. Retried requests must not cause duplicate financial postings.
- Concurrent financial operations: Multiple transfers or withdrawals may be initiated against the same wallet simultaneously. The database must prevent conflicting balance updates and overspending.
- Identity verification and fraud: Customers may submit invalid identity information or engage in suspicious transaction patterns. KYC records and risk flags must support investigation and control.
- Financial auditability: Every completed financial operation must have a traceable record. Reversals must preserve the original transaction history rather than erase it.
- Data security and privacy: Customer identity, account details, and transaction histories require appropriate access controls and protection.

### 1.2 Enterprise Profile: CarbonPay Financial Technologies

CarbonPay Financial Technologies is a hypothetical Nigerian digital financial services platform offering:

- Digital naira wallets for individuals.
- Merchant accounts for businesses.
- Wallet deposits and withdrawals.
- Peer-to-peer transfers.
- Utility and other bill payments.
- Linked debit and virtual cards.
- Saved bank beneficiaries.
- Customer identity verification.
- Automated transaction monitoring and fraud investigation.

The platform serves individuals, freelancers, and small businesses. Customers interact through a mobile application or web interface, while internal services process financial transactions and compliance checks.

PostgreSQL 16 serves as the platform's primary relational database, responsible for enforcing data integrity, maintaining relationships between entities, and supporting transactional operations.

The central business objective is to provide secure, consistent, auditable, and reliable digital financial services, even when requests are retried, multiple operations occur simultaneously, or external payment services fail.

## 2. Regulatory, Compliance, and Security Framework

CarbonPay operates in a simulated Nigerian financial services environment. Its database design should reflect relevant compliance and security considerations without assuming that a database schema alone guarantees regulatory compliance.

| Requirement                    | Relevance to CarbonPay                                               | Existing schema implementation                      |
| ------------------------------ | -------------------------------------------------------------------- | --------------------------------------------------- |
| Customer identity verification | Establish customer identity before enabling applicable services      | `customers`, `kyc_records`                          |
| Account number validation      | Maintain correctly formatted 10-digit account numbers in this model  | `accounts.account_number`                           |
| Payment card data minimization | Avoid storing full card numbers and CVVs in the application database | `cards.last_four`                                   |
| Customer data protection       | Restrict access to personal and financial information                | Customer relationships and database access controls |
| Anti-fraud monitoring          | Identify and investigate suspicious transactions                     | `fraud_flags`                                       |
| Financial auditability         | Preserve financial transaction and ledger history                    | `transactions`, `ledger_entries`                    |
| Financial accuracy             | Avoid floating-point arithmetic for monetary values                  | `NUMERIC(19,4)`                                     |
| Duplicate request protection   | Prevent a retried request from being processed as a new transaction  | `transactions.idempotency_key`                      |

Relevant Nigerian requirements may include applicable Central Bank of Nigeria rules, data protection obligations under the Nigeria Data Protection Act 2023, and relevant anti-money-laundering and counter-terrorist-financing requirements. Actual obligations depend on the services provided, the platform's authorization, and the applicable regulations.

Security limitation: Your current tables provide useful structural controls, but production deployment would also require appropriate authentication, authorization, encryption, audit logging, secure credential management, and operational monitoring.

## 3. Database Users and Actor Personas

The `carbonpay_db` database supports several categories of users and system components. Each has different access requirements and responsibilities.

1\. Customers and Merchants

External users

Individuals and businesses use the platform to manage wallets, view balances, send money, pay bills, save beneficiaries, and manage linked cards. They should only access accounts and information they are authorized to use.

2\. KYC and Compliance Officers

Identity verification and compliance

Review identity submissions, resolve verification failures, investigate suspicious activity, and document compliance decisions. Access to sensitive identity information must be restricted.

3\. Customer Support Agents

Customer service and dispute resolution

Investigate failed transfers, identify delayed transactions, and help customers understand their account activity. They should not have unrestricted permission to modify ledger records.

4\. Transaction Processing Engine

Core financial operations

Validates financial requests, coordinates atomic database transactions, updates account balances, writes ledger entries, and processes payment gateway responses.

5\. Fraud Monitoring Service

Risk detection

Evaluates transactions against configured risk rules and creates fraud flags for further investigation. It should not be able to alter completed financial history arbitrarily.

6\. Internal and External Auditors

Independent verification

Review historical transactions, compare account balances with ledger totals, identify inconsistencies, and verify whether financial postings are balanced. Their database access should normally be read-only.

### 3.1 Database access principles

The platform should apply the principle of least privilege:

- Customers access only their authorized accounts and transaction information.
- Support agents receive restricted read access and approved dispute-management functions.
- Compliance officers can review KYC and fraud records according to their responsibilities.
- The transaction engine receives narrowly scoped permissions needed for financial processing.
- Auditors receive read-only access to financial records and reconciliation results.

These permissions are implementation requirements; they are not automatically established by the eight tables you have created.

## 4. System Scope and Major Data Domains

Your existing schema contains eight relational tables, organized into five functional domains.

### Domain 1 — Customer Identity and KYC

`customers` · `kyc_records`

Stores customer profiles, account-holder types, statuses, identity submissions, and verification outcomes.

### Domain 2 — Wallets and Payment Instruments

`accounts` · `cards` · `beneficiaries`

Manages wallet accounts, account balances, saved bank recipients, and masked card information.

### Domain 3 — Transaction Processing and Accounting

`transactions` · `ledger_entries`

Records financial events, tracks their statuses, prevents duplicate requests, and stores debit and credit postings.

### Domain 4 — Fraud and Risk Management

`fraud_flags`

Captures suspicious transactions, risk scores, investigation reasons, and review statuses.

### Domain 5 — Reconciliation and Audit

Uses `accounts`, `transactions`, and `ledger_entries`

Verifies ledger consistency, checks transaction histories, and compares cached account balances with ledger-derived balances.

### 4.1 Customer and identity management

The `customers` table is the central entity representing individuals and merchants.

Each customer has a unique identifier, name, email, phone number, customer type, status, and creation timestamp.

The `kyc_records` table stores identity verification submissions. A customer may submit identification more than once, allowing rejected or unsuccessful submissions to be followed by new attempts.

Relationship: One customer can have many KYC records, but each KYC record belongs to one customer.

### 4.2 Wallets and payment instruments

The `accounts` table stores each wallet's account number, currency, current cached balance, status, and opening timestamp.

A customer can own multiple accounts under the current design. Account statuses determine whether an account is active, frozen, or closed.

The `beneficiaries` table stores bank recipients saved by a customer. Its composite unique constraint prevents the same bank and account number from being saved twice by the same customer.

The `cards` table stores limited card metadata, including the last four digits, type, expiry date, and status. Full card numbers and CVVs are intentionally absent.

### 4.3 Transaction processing and double-entry accounting

The `transactions` table represents the business event, such as a deposit, withdrawal, transfer, bill payment, or reversal.

Its idempotency key identifies a request so that a repeated request can be recognized rather than applied twice.

The `ledger_entries` table records the account-level financial postings associated with transactions. Its foreign keys connect each entry to a transaction and an account.

For a simple wallet transfer of ₦5,000:

- The sender's wallet receives a debit entry of ₦5,000.
- The recipient's wallet receives a credit entry of ₦5,000.

The amount debited must equal the amount credited for that transfer. A production-quality implementation must enforce this rule through transaction-processing logic and appropriate database safeguards; your existing table constraints alone do not guarantee that every transaction has balanced entries.

### 4.4 Fraud detection and investigation

The `fraud_flags` table associates a risk flag with a transaction.

Each flag stores a reason, risk score between 0 and 100, status, and timestamp. A high risk score can trigger review, but the score itself does not automatically prove fraud.

Possible scenarios include repeated transfers in a short period, unusual transaction amounts, multiple failed attempts, or suspicious account activity.

### 4.5 Reconciliation and financial audit

Reconciliation compares the platform's cached account balances against the balances derived from ledger entries.

Auditors can also check whether transactions have the expected debit and credit postings and whether reversals correctly compensate for earlier financial movements.

One important distinction: the current schema does not contain a separate reconciliation table. Reconciliation can be implemented using SQL queries initially, with additional tables introduced later if you need stored reconciliation runs, discrepancies, and resolution histories.

## 5. Key Business Workflows and Operational Lifecycles

### 5.1 Customer onboarding and KYC verification

When a new customer joins CarbonPay, the platform must establish their identity and create the appropriate wallet account.

Step 1: Customer registration

Create a record in `customers`.

Step 2: Identity submission

Insert the customer's identity details into `kyc_records` with status `PENDING`.

Step 3: Verification review

An authorized verification process determines whether the submission is accepted or rejected.

VERIFIED

Record verification outcome and timestamp.

REJECTED

Record the outcome and permit resubmission where appropriate.

Business rule: Customer registration alone must not be treated as proof of identity verification. Whether a customer may transact depends on the platform's applicable onboarding and risk policies.

Your current schema supports the core recordkeeping, but it does not automatically prevent an unverified customer from opening or using a wallet.

### 5.2 Wallet-to-wallet transfer

Assume Customer A transfers ₦5,000 to Customer B.

The database must ensure that the sender has sufficient funds, both accounts are eligible for the operation, and concurrent transactions cannot spend the same funds twice.

1\. Receive transfer request

Validate the amount and request details.

2\. Check idempotency

Look up `transactions.idempotency_key`. Return the prior result if the same request was already processed.

3\. Lock the relevant accounts

Use `SELECT ... FOR UPDATE` in a database transaction and lock accounts in a consistent order.

4\. Validate account status and funds

Confirm both accounts are eligible and the sender can cover the transfer.

5\. Post the financial transaction

Insert the transaction, debit and credit ledger entries, and update both cached balances atomically.

6\. Commit or roll back

Commit all changes together on success. Roll back the entire database operation if a required step fails.

The transfer should satisfy these conditions:

- The sender's balance decreases by ₦5,000.
- The recipient's balance increases by ₦5,000.
- The debit and credit entries have the same amount.
- A retry with the same idempotency key must not cause a second transfer.
- A failed operation must not leave a partially posted transfer.

Important accounting consideration: Your current `ledger_entries` table only references customer accounts. That can be sufficient for a simplified wallet-to-wallet transfer exercise, but a production system must also model appropriate funding, clearing, settlement, and expense or revenue accounts for external financial movements.

### 5.3 Deposit and withdrawal processing

A customer deposits ₦20,000 into their wallet.

1. The platform receives the deposit request.
2. The transaction engine verifies the request identifier and validates the deposit.
3. The platform confirms the external payment or funding event as appropriate.
4. A deposit transaction is recorded.
5. Corresponding ledger postings are created and the wallet balance is updated.
6. The database transaction commits once the required internal changes succeed.

A withdrawal follows a similar process, except the wallet is debited.

External payment confirmation must be handled carefully: a database commit cannot guarantee that a separate bank or payment gateway has successfully settled the funds. External settlement therefore requires reliable status tracking, retry handling, and reconciliation.

### 5.4 Transaction reversal

Suppose a customer's wallet is debited ₦10,000 for a transfer, but the external transfer subsequently fails.

The platform must not delete the original transaction or silently edit its ledger history.

Instead:

1. Identify and verify the original transaction.
2. Create a compensating transaction with `txn_type = 'REVERSAL'`.
3. Link it to the original using `reversal_of`.
4. Post the appropriate compensating ledger entries.
5. Update the affected balances atomically.
6. Update the original transaction's status according to the agreed reversal lifecycle.

The database constraint already ensures that a `REVERSAL` transaction must reference an original transaction. However, it does not prevent multiple reversal transactions from referencing the same original. That additional business rule must be enforced if only one reversal is allowed.

### 5.5 Fraud detection workflow

A customer suddenly initiates several unusually large transfers.

The risk monitoring service evaluates the transaction pattern and creates a fraud flag when configured rules are triggered.

Transaction received

Transaction recorded in `transactions`.

Risk evaluation

Automated rules evaluate the transaction and assign a risk score.

Fraud flag created

Store the transaction reference, reason, risk score, and review status.

Investigation and resolution

An authorized reviewer marks the case as cleared or confirmed.

Your schema supports recording flags and their statuses. It does not yet record the assigned investigator, review notes, or a complete history of status changes. Those features can be added in a later development phase.

## 6. Architectural Invariants and Database Constraints

Your existing PostgreSQL schema already implements several important data integrity rules.

| Invariant                       | Existing SQL mechanism                         | Purpose                                                    |
| ------------------------------- | ---------------------------------------------- | ---------------------------------------------------------- |
| Unique customer identity fields | `UNIQUE` on email and phone                    | Prevent duplicate email addresses and phone numbers        |
| Valid customer type             | `CHECK` constraint                             | Restrict customers to `INDIVIDUAL` or `MERCHANT`           |
| Valid account number format     | Regex `CHECK`                                  | Enforce a 10-digit account number                          |
| Non-negative wallet balance     | `CHECK (balance >= 0)`                         | Reject negative account balances                           |
| Exact monetary precision        | `NUMERIC(19,4)`                                | Avoid binary floating-point rounding errors                |
| Unique request identifier       | `UNIQUE (idempotency_key)`                     | Identify duplicate transaction requests                    |
| Valid transaction amount        | `CHECK (amount > 0)`                           | Reject zero or negative transaction amounts                |
| Valid fraud risk score          | `CHECK` between 0 and 100                      | Restrict risk scores to the defined range                  |
| Valid reversal relationship     | `CHECK` involving `txn_type` and `reversal_of` | Require reversal transactions to reference an original     |
| Referential integrity           | Foreign keys                                   | Prevent references to nonexistent parent records           |
| Historical record protection    | `ON DELETE RESTRICT` on financial references   | Prevent deletion of referenced financial history           |
| Masked card metadata            | `last_four` format check                       | Restrict the stored card identifier to four numeric digits |

### 6.1 Additional integrity requirements to investigate

For an advanced database project, you should critically evaluate the difference between rules already implemented and rules that still require additional enforcement.

Not fully enforced

Double-entry balance

Your table allows individual ledger entries but does not guarantee that every completed transaction has matching debit and credit totals. A deferred constraint trigger or controlled posting procedure may be required.

Not fully enforced

Cached balance consistency

The `accounts.balance` value can differ from the balance reconstructed from the ledger if an application changes one without correctly updating the other.

Not fully enforced

KYC eligibility

The current schema does not enforce a rule that only verified customers may transact.

Not fully enforced

Transaction status transitions

The status constraint permits valid status values, but does not prevent an invalid transition such as moving a failed transaction directly to a completed state.

Not fully enforced

Duplicate reversals

The schema does not enforce a one-reversal-per-original-transaction rule.

Design consideration

Idempotency semantics

A unique key prevents duplicate key values, but the application must still handle concurrent retries safely and verify that a repeated key represents the same request and amount.

These limitations are not reasons to discard your schema. They provide excellent material for your database testing, transaction management, and optimization portfolios.

## 7. Mapping to the MIT 8103 Portfolio Roadmap

Following the structure of your reference case study, CarbonPay can support a progressive five-portfolio database project.

## 01

Portfolio 1 — Relational Design and Constraints

Current stage

- Create and document the eight existing tables.
- Explain primary keys, foreign keys, cardinality, and normalization.
- Test check constraints, uniqueness, and referential integrity.
- Document limitations in financial invariants.

## 02

Portfolio 2 — Query Optimization

- Develop queries for customer lookup, transaction histories, and fraud investigations.
- Use `EXPLAIN ANALYZE` to inspect query execution.
- Compare appropriate indexes and composite indexes.
- Measure performance before and after optimization.

## 03

Portfolio 3 — Transactions and Concurrency

- Implement atomic wallet transfers.
- Demonstrate row-level locking with `SELECT ... FOR UPDATE`.
- Simulate simultaneous withdrawals.
- Test idempotent retries, rollback, deadlocks, and isolation levels.

## 04

Portfolio 4 — Polyglot Persistence and NoSQL

- Explore storing flexible risk-event details and payment gateway payloads in MongoDB.
- Keep authoritative financial postings in PostgreSQL.
- Compare relational and document-based storage.
- Explain consistency and data ownership across the two databases.

## 05

Portfolio 5 — Distributed and Cloud Architecture

- Investigate PostgreSQL replication and failover.
- Explore partitioning large transaction and ledger tables.
- Design backup, recovery, and monitoring procedures.
- Evaluate availability and consistency during infrastructure failures.

## 8. Practical Assessment Tasks

Use these tasks to demonstrate that your CarbonPay database is functional, not just created.

## Your project checklist

0 of 7 complete

Validate table relationships

Verify all eight tables exist and confirm their foreign-key relationships.

Test constraint failures

Attempt duplicate emails, malformed account numbers, negative balances, and invalid risk scores. Confirm PostgreSQL rejects them.

Populate sample data

Insert fictional customers, KYC records, wallets, beneficiaries, cards, transactions, ledger entries, and fraud flags in dependency order.

Implement a wallet transfer

Write a transaction-safe PostgreSQL routine or application operation that debits one wallet and credits another atomically.

Test concurrent withdrawals

Use two database sessions to attempt withdrawals that together exceed the available balance. Confirm the final balance remains valid.

Verify ledger reconciliation

Write SQL queries that compare cached wallet balances against ledger-derived balances and identify unbalanced transactions.

Document schema limitations

Explain which integrity rules are declarative constraints and which depend on application logic, triggers, or stored procedures.

&#x20; Copy checklist&#x20;

## 9. Recommended next step

Since you have already created your tables in PostgreSQL, do not recreate them unnecessarily. Your next task should be to validate the schema and begin inserting fictional test data.

I recommend following this sequence:

1. Confirm that all eight tables exist in the correct database.
2. Insert a small dataset with two customers and two wallets.
3. Test a ₦5,000 wallet transfer using an explicit database transaction.
4. Verify that the balances and ledger entries agree.
5. Test a duplicate request and a concurrent withdrawal scenario.
6. Document your results and any changes needed to strengthen the schema.

One important point for your assessment: creating tables successfully demonstrates that the DDL executed, but it does not yet prove that the database meets every financial integrity requirement.

Your existing schema is a good starting foundation for the CarbonPay case study. The strongest next deliverable would be a Portfolio 1 implementation and testing script that works directly with your eight existing PostgreSQL tables.