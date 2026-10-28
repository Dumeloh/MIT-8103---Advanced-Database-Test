
/*
 * MIT 8103 Portfolio 4 - Carbon Case Study
 * Step 4: Seed 5,000 KYC profiles and 100,000 audit events.
 *
 * Database: carbon_nosql
 * Customer IDs: 1â€“5000, matching the PostgreSQL customers table.
 *
 * WARNING: This script clears existing documents in kyc_profiles
 * and audit_events before inserting the seed data.
 */

const carbon = db.getSiblingDB("carbon_nosql");

const CUSTOMER_COUNT = 5000;
const EVENT_COUNT = 100000;
const BATCH_SIZE = 5000;

print("Starting Carbon MongoDB seed process...");

// Clear existing seedable documents.
carbon.kyc_profiles.deleteMany({});
carbon.audit_events.deleteMany({});

const tiers = [1, 2, 3];
const statuses = ["PENDING", "VERIFIED", "REJECTED"];
const documentTypes = [
    "BVN",
    "NIN",
    "PASSPORT",
    "DRIVERS_LICENCE",
    "UTILITY_BILL"
];

const eventTypes = [
    "LOGIN_SUCCESS",
    "LOGIN_FAILED",
    "PIN_CHANGED",
    "TRANSFER_INITIATED",
    "KYC_UPGRADED",
    "FRAUD_FLAG"
];

// Simple deterministic pseudo-random generator for repeatable seed data.
let seed = 8103;
function random() {
    seed = (seed * 48271) % 2147483647;
    return (seed - 1) / 2147483646;
}

function pick(items) {
    return items[Math.floor(random() * items.length)];
}

function makeDocument(customerId, index) {
    return {
        type: documentTypes[index % documentTypes.length],
        number: "CARBON-" + customerId + "-" + (index + 1)
    };
}

// Create 5,000 KYC profiles.
let kycBatch = [];

for (let customerId = 1; customerId <= CUSTOMER_COUNT; customerId++) {
    const tierRoll = random();
    const tier = tierRoll < 0.55 ? 1 : tierRoll < 0.88 ? 2 : 3;
    const documentCount = tier === 1 ? 1 : tier === 2 ? 2 : 3;

    const profile = {
        customer_id: customerId,
        tier: tier,
        status: pick(statuses),
        documents: Array.from(
            { length: documentCount },
            (_, index) => makeDocument(customerId, index)
        ),
        created_at: new Date(
            Date.now() - Math.floor(random() * 180 * 24 * 60 * 60 * 1000)
        )
    };

    if (tier === 3) {
        profile.risk_notes = "Enhanced review required";
    }

    kycBatch.push(profile);

    if (kycBatch.length >= BATCH_SIZE) {
        carbon.kyc_profiles.insertMany(kycBatch);
        kycBatch = [];
    }
}

if (kycBatch.length > 0) {
    carbon.kyc_profiles.insertMany(kycBatch);
}

// Create 100,000 audit events over the last 90 days.
let eventBatch = [];
const now = Date.now();
const ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;

for (let i = 1; i <= EVENT_COUNT; i++) {
    const eventType = pick(eventTypes);

    const event = {
        customer_id: Math.floor(random() * CUSTOMER_COUNT) + 1,
        event_type: eventType,
        ts: new Date(now - Math.floor(random() * ninetyDaysMs)),
        details: {
            source: pick(["mobile", "web", "api"]),
            reference: "CARBON-EVT-" + i
        }
    };

    if (eventType === "TRANSFER_INITIATED") {
        event.details.amount = NumberDecimal(
            (10 + random() * 99990).toFixed(2)
        );
    }

    if (eventType === "LOGIN_FAILED" || eventType === "FRAUD_FLAG") {
        event.details.reason = pick([
            "INVALID_CREDENTIALS",
            "UNUSUAL_ACTIVITY",
            "DEVICE_REVIEW"
        ]);
    }

    eventBatch.push(event);

    if (eventBatch.length >= BATCH_SIZE) {
        carbon.audit_events.insertMany(eventBatch);
        eventBatch = [];
    }

    if (i % 25000 === 0) {
        print("Prepared " + i + " of " + EVENT_COUNT + " audit events...");
    }
}

if (eventBatch.length > 0) {
    carbon.audit_events.insertMany(eventBatch);
}

// Verify the final counts.
print("");
print("CARBON SEED VERIFICATION");
print("KYC profiles: " + carbon.kyc_profiles.countDocuments({}));
print("Audit events: " + carbon.audit_events.countDocuments({}));
print("KYC tier distribution:");

carbon.kyc_profiles.aggregate([
    { $group: { _id: "$tier", count: { $sum: 1 } } },
    { $sort: { _id: 1 } }
]).forEach(doc => printjson(doc));

print("Audit event type distribution:");

carbon.audit_events.aggregate([
    { $group: { _id: "$event_type", count: { $sum: 1 } } },
    { $sort: { _id: 1 } }
]).forEach(doc => printjson(doc));

print("Sample tier-3 Carbon KYC profile:");
printjson(carbon.kyc_profiles.findOne({ tier: 3 }));

print("Carbon seed process finished.");


