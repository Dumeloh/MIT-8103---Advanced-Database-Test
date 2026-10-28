# MIT 8103 Portfolio 4: MongoDB and NoSQL
## Carbon Fintech Case Study

### 1. Project Overview

This project demonstrates how MongoDB can complement a relational database in a fintech platform such as Carbon. The focus is on managing customer Know Your Customer (KYC) profiles, audit events, and login sessions using a document-oriented database.

The project uses MongoDB Atlas and MongoDB Shell (`mongosh`) to create collections, enforce schema validation, generate test data, perform CRUD operations, run aggregation pipelines, and evaluate query performance using indexes and `explain()`.

### 2. Database Design and Technology Choice

The project uses MongoDB for data that benefits from flexible document structures and high-volume event storage.

The three collections are:

- **`kyc_profiles`** — stores customer KYC information, including verification status, tier, document details, and creation date.
- **`audit_events`** — stores customer activity events, such as successful or failed logins, PIN changes, transfer initiation events, KYC upgrades, and fraud flags.
- **`login_sessions`** — supports login-session records and automatic expiry through a time-to-live (TTL) index.

MongoDB is used alongside PostgreSQL rather than as a replacement for it. PostgreSQL remains the appropriate choice for core financial records, including wallets, balances, transfers, and ledger entries, where relational integrity, precise numeric values, and reliable multi-record transactions are essential.

The `customer_id` field in MongoDB corresponds to the customer identifier in PostgreSQL. This is a logical relationship; MongoDB does not enforce a foreign key directly against the PostgreSQL database.
