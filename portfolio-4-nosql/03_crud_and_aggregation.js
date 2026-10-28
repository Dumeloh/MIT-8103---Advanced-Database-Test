
/*
 * MIT 8103 Portfolio 4 - Carbon Case Study
 * Step 5: CRUD operations and four aggregation pipelines.
 *
 * Database: carbon_nosql
 * IMPORTANT: Uses a temporary test customer ID (9999999).
 * Does not delete or modify the seeded KYC profiles or audit events.
 */

const carbon = db.getSiblingDB("carbon_nosql");

print("\n========================================");
print("CARBON CRUD OPERATIONS");
print("========================================");

// Use a separate test ID so seeded records remain untouched.
const testCustomerId = 9999999;

// Clean up only this script's own previous test record.
carbon.kyc_profiles.deleteMany({
    customer_id: testCustomerId
});

// CREATE: insert a temporary KYC profile.
const createResult = carbon.kyc_profiles.insertOne({
    customer_id: testCustomerId,
    tier: 1,
    status: "PENDING",
    documents: [
        {
            type: "BVN",
            number: "CARBON-CRUD-TEST-9999999"
        }
    ],
    created_at: new Date()
});

print("\nCREATE: Inserted temporary KYC profile");
printjson(createResult);

// READ: retrieve the test profile.
print("\nREAD: Temporary KYC profile");
printjson(
    carbon.kyc_profiles.findOne({
        customer_id: testCustomerId
    })
);

// UPDATE: change its status.
const updateResult = carbon.kyc_profiles.updateOne(
    { customer_id: testCustomerId },
    { $set: { status: "VERIFIED" } }
);

print("\nUPDATE: Changed temporary profile status");
printjson(updateResult);

// DELETE: remove only the temporary test profile.
const deleteResult = carbon.kyc_profiles.deleteOne({
    customer_id: testCustomerId
});

print("\nDELETE: Removed temporary test profile");
printjson(deleteResult);

// Confirm the seeded data remains present.
print("\nSEEDED DATA COUNTS AFTER CRUD");
print("KYC profiles: " + carbon.kyc_profiles.countDocuments({}));
print("Audit events: " + carbon.audit_events.countDocuments({}));

print("\n========================================");
print("CARBON AGGREGATION PIPELINES");
print("========================================");

// PIPELINE 1: Count KYC profiles by tier.
print("\nPIPELINE 1: KYC profiles by tier");
carbon.kyc_profiles.aggregate([
    {
        $group: {
            _id: "$tier",
            profile_count: { $sum: 1 }
        }
    },
    { $sort: { _id: 1 } }
]).forEach(printjson);

// PIPELINE 2: Count audit events by event type.
print("\nPIPELINE 2: Audit events by event type");
carbon.audit_events.aggregate([
    {
        $group: {
            _id: "$event_type",
            event_count: { $sum: 1 }
        }
    },
    { $sort: { event_count: -1 } }
]).forEach(printjson);

// PIPELINE 3: Find the most active customers by audit-event count.
print("\nPIPELINE 3: Top 10 customers by audit-event count");
carbon.audit_events.aggregate([
    {
        $group: {
            _id: "$customer_id",
            event_count: { $sum: 1 }
        }
    },
    { $sort: { event_count: -1 } },
    { $limit: 10 }
]).forEach(printjson);

// PIPELINE 4: Join KYC profiles with audit events using $lookup.
print("\nPIPELINE 4: KYC profiles joined to audit-event summaries");
carbon.kyc_profiles.aggregate([
    {
        $lookup: {
            from: "audit_events",
            localField: "customer_id",
            foreignField: "customer_id",
            as: "customer_events"
        }
    },
    {
        $project: {
            _id: 0,
            customer_id: 1,
            tier: 1,
            status: 1,
            audit_event_count: { $size: "$customer_events" }
        }
    },
    { $sort: { audit_event_count: -1 } },
    { $limit: 10 }
]).forEach(printjson);

print("\nCARBON CRUD AND AGGREGATION COMPLETED");


