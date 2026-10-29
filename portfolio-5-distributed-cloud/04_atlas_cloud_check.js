
'use strict';

// Carbon Portfolio 5: MongoDB Atlas replication check.
// Set MONGODB_URI to your own Atlas connection string before running.
// Never commit real credentials or connection strings to Git.

const { MongoClient, ReadPreference } = require('mongodb');

async function main() {
    const uri = process.env.MONGODB_URI;

    if (!uri) {
        throw new Error(
            'MONGODB_URI is not set. Configure your MongoDB Atlas connection string first.'
        );
    }

    const client = new MongoClient(uri, {
        retryWrites: true,
        w: 'majority'
    });

    try {
        await client.connect();

        const admin = client.db('admin');
        const status = await admin.command({ hello: 1 });

        console.log('=== Carbon Atlas: replica-set status ===');
        console.log({
            setName: status.setName ?? null,
            isWritablePrimary: status.isWritablePrimary ?? false,
            isSecondary: status.secondary ?? false,
            hosts: status.hosts ?? [],
            passives: status.passives ?? []
        });

        const db = client.db('carbon_cloud_test');
        const collection = db.collection('replication_checks');

        const testId = `carbon-check-${Date.now()}`;

        console.log('=== Carbon Atlas: majority write ===');

        const writeResult = await collection.insertOne(
            {
                _id: testId,
                project: 'Carbon',
                purpose: 'Portfolio 5 replication check',
                createdAt: new Date()
            },
            {
                writeConcern: {
                    w: 'majority',
                    wtimeoutMS: 10000
                }
            }
        );

        console.log({
            acknowledged: writeResult.acknowledged,
            insertedId: writeResult.insertedId
        });

        console.log('=== Carbon Atlas: primary read ===');

        const primaryRead = await collection.findOne(
            { _id: testId },
            { readPreference: ReadPreference.primary }
        );

        console.log({ found: Boolean(primaryRead) });

        console.log('=== Carbon Atlas: secondary read attempt ===');

        try {
            const secondaryDb = client.db('carbon_cloud_test', {
                readPreference: ReadPreference.secondary
            });

            const secondaryRead = await secondaryDb
                .collection('replication_checks')
                .findOne({ _id: testId });

            console.log({
                found: Boolean(secondaryRead),
                note: 'A secondary read succeeded; replication visibility was observed.'
            });
        } catch (error) {
            console.log({
                secondaryReadSucceeded: false,
                message: error.message
            });

            console.log(
                'A secondary read may be unavailable if no eligible secondary is reachable.'
            );
        }
    } finally {
        await client.close();
    }
}

main().catch((error) => {
    console.error('Carbon Atlas check failed:', error.message);
    process.exitCode = 1;
});
