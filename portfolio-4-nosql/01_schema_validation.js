
/*
 * MIT 8103 Portfolio 4 - Carbon Case Study
 * Step 1: Create MongoDB collections with schema validation.
 *
 * Database: carbon_nosql
 * Collections: kyc_profiles, audit_events, login_sessions
 *
 * IMPORTANT:
 * This script drops and recreates these three collections.
 * Review the effects before running it if they already contain data.
 */

const carbon = db.getSiblingDB('carbon_nosql');

// Remove existing collections so this script can recreate their validators.
// Do not run this against collections containing data you need to preserve.
['kyc_profiles', 'audit_events', 'login_sessions'].forEach(function (name) {
    carbon.getCollection(name).drop();
});

// KYC: one profile per customer.
// Identity documents are embedded because they belong to the same profile.
carbon.createCollection('kyc_profiles', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['customer_id', 'tier', 'status', 'documents', 'created_at'],
            properties: {
                customer_id: {
                    bsonType: ['int', 'long', 'double', 'decimal'],
                    minimum: 1,
                    description: 'Must match customers.customer_id in PostgreSQL'
                },
                tier: {
                    bsonType: ['int', 'long', 'double', 'decimal'],
                    minimum: 1,
                    maximum: 3
                },
                status: {
                    enum: ['PENDING', 'VERIFIED', 'REJECTED']
                },
                documents: {
                    bsonType: 'array',
                    minItems: 1,
                    items: {
                        bsonType: 'object',
                        required: ['type', 'number'],
                        properties: {
                            type: {
                                enum: [
                                    'BVN',
                                    'NIN',
                                    'PASSPORT',
                                    'DRIVERS_LICENCE',
                                    'UTILITY_BILL'
                                ]
                            },
                            number: { bsonType: 'string' }
                        }
                    }
                },
                created_at: { bsonType: 'date' }
            }
        }
    },
    validationAction: 'error'
});

// Audit events are stored separately because the log grows continuously.
carbon.createCollection('audit_events', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['customer_id', 'event_type', 'ts', 'details'],
            properties: {
                customer_id: {
                    bsonType: ['int', 'long', 'double', 'decimal'],
                    minimum: 1
                },
                event_type: {
                    enum: [
                        'LOGIN_SUCCESS',
                        'LOGIN_FAILED',
                        'PIN_CHANGED',
                        'TRANSFER_INITIATED',
                        'KYC_UPGRADED',
                        'FRAUD_FLAG'
                    ]
                },
                ts: { bsonType: 'date' },
                details: { bsonType: 'object' }
            }
        }
    },
    validationAction: 'error'
});

// Login sessions are short-lived. The TTL index will be added later.
carbon.createCollection('login_sessions');

print('Collections now in carbon_nosql:');
carbon.getCollectionNames().forEach(function (name) {
    print('  - ' + name);
});

// Test validation by attempting to insert an invalid KYC document.
try {
    carbon.kyc_profiles.insertOne({
        customer_id: 1,
        status: 'MAYBE'
    });
    print('FAIL: the invalid KYC document was accepted');
} catch (error) {
    if (error.code === 121) {
        print(
            'PASS: invalid KYC document rejected -> ' +
            error.codeName + ' (code ' + error.code + ')'
        );
    } else {
        throw error;
    }
}


