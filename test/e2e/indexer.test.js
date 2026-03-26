const { PG_OPTIONS, TX_PATH, INDEXER_URL, getTopic, loadTransactions} = require('./setup');
const { Client } = require("pg");
const fs = require('fs/promises');

let client;
let eventRecords;
let transactions;

beforeAll(async () => {
    client = new Client(PG_OPTIONS);
    await client.connect();

    eventRecords = await client.query(`SELECT * FROM event_records`)
        .then(r => r.rows)
        .catch(e => { throw e; });

    transactions = await loadTransactions(TX_PATH);
});

afterAll(async () => { await client.end(); });

test('Indexer ', () => {
    expect(eventRecords.length).toBe(transactions.size);

    eventRecords.forEach(er => {
       const tx = transactions.get(er.tx_hash);
       expect(tx).toBeDefined();
       expect(er.contract_address).toBe(tx.contractAddress);
       expect(er.topic).toBe(getTopic(tx));
    });
});

describe('GET /state', () => {
    let res;
    let state;

    beforeAll(async () => {
        res = await fetch(`${INDEXER_URL}/state`);
        state = await res.json();
    });

    test('returns 200 with JSON content-type', () => {
        expect(res.status).toBe(200);
        expect(res.headers.get('content-type')).toMatch(/application\/json/);
    });

    test('response is an object', () => {
        expect(typeof state).toBe('object');
        expect(state).not.toBeNull();
        expect(Array.isArray(state)).toBe(false);
    });

    test('keys include all indexed event topics', () => {
        const topics = [...new Set(eventRecords.map(er => er.topic))];
        for (const topic of topics) {
            expect(state).toHaveProperty(topic);
        }
    });

    test('values are non-negative integers', () => {
        for (const blockNumber of Object.values(state)) {
            expect(Number.isInteger(blockNumber)).toBe(true);
            expect(blockNumber).toBeGreaterThanOrEqual(0);
        }
    });

    test('state block numbers are >= max indexed block number per topic', async () => {
        for (const [topic, lastBlock] of Object.entries(state)) {
            const { rows } = await client.query(
                `SELECT MAX(block_number) AS max FROM event_records WHERE topic = $1`,
                [topic]
            );
            const maxIndexed = Number(rows[0].max ?? 0);
            expect(lastBlock).toBeGreaterThanOrEqual(maxIndexed);
        }
    });
});

describe('GET /health', () => {
    test('returns 200', async () => {
        const res = await fetch(`${INDEXER_URL}/health`);
        expect(res.status).toBe(200);
    });
});
