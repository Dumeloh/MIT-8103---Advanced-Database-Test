
/*
 * MIT 8103 Portfolio 4 - Carbon Case Study
 * Step 6: Indexes and query performance using explain().
 *
 * Database: carbon_nosql
 *
 * Indexes:
 * 1. Customer ID and timestamp for customer audit history.
 * 2. Event type and timestamp for event investigations.
 * 3. Unique customer ID for KYC profiles.
 * 4. TTL index to expire login sessions after one hour.
 *
 * This script does not delete or replace existing records.
 */

const carbon = db.getSiblingDB("carbon_nosql");

print("\n========================================");
print("CARBON INDEXES AND QUERY PERFORMANCE");
print("========================================");

// 1. Show query execution statistics before adding indexes.
print("\n1. AUDIT QUERY EXPLAIN BEFORE INDEXING");

printjson(
    carbon.audit_events
        .find({ customer_id: 100 })
        .sort({ ts: -1 })
        .explain("executionStats")
);

// 2. Create an index for customer audit history.
print("\n2. CREATING CUSTOMER AUDIT INDEX");

printjson(
    carbon.audit_events.createIndex(
        { customer_id: 1, ts: -1 },
        { name: "customer_id_ts_desc" }
    )
);

// 3. Create an index for event-type investigations.
print("\n3. CREATING EVENT TYPE INDEX");

printjson(
    carbon.audit_events.createIndex(
        { event_type: 1, ts: -1 },
        { name: "event_type_ts_desc" }
    )
);

// 4. Create a unique index for KYC customer IDs.
print("\n4. CREATING UNIQUE KYC CUSTOMER INDEX");

printjson(
    carbon.kyc_profiles.createIndex(
        { customer_id: 1 },
        { unique: true, name: "unique_kyc_customer_id" }
    )
);

// 5. Create a TTL index for login sessions.
// MongoDB removes a session when its created_at date is more than
// 3600 seconds (one hour) in the past.
print("\n5. CREATING ONE-HOUR LOGIN SESSION TTL INDEX");

printjson(
    carbon.login_sessions.createIndex(
        { created_at: 1 },
        { expireAfterSeconds: 3600, name: "login_session_ttl" }
    )
);

// 6. Explain the same audit query after indexing.
print("\n6. AUDIT QUERY EXPLAIN AFTER INDEXING");

printjson(
    carbon.audit_events
        .find({ customer_id: 100 })
        .sort({ ts: -1 })
        .explain("executionStats")
);

// 7. Display all indexes.
print("\n7. AUDIT EVENT INDEXES");

printjson(carbon.audit_events.getIndexes());

print("\n8. KYC PROFILE INDEXES");

printjson(carbon.kyc_profiles.getIndexes());

print("\n9. LOGIN SESSION INDEXES");

printjson(carbon.login_sessions.getIndexes());

print("\nCARBON INDEX AND EXPLAIN SCRIPT COMPLETED");


