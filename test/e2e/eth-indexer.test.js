'use strict';

const fs = require('fs');
const { Client } = require('pg');
const { PG_OPTIONS, TX_PATH, INDEXER_URL, API_URL, getTopic, loadTransactions, selectEventRecords} = require('./setup');

// ── Broadcast fixtures ────────────────────────────────────────────────────────

const broadcast = JSON.parse(fs.readFileSync(TX_PATH, 'utf8'));

// Unique contract addresses touched by GenerateEvents
const contractAddresses = [...new Set(
    broadcast.transactions.map(tx => tx.transaction.to.toLowerCase())
)];

// tx hash → receipt
const receiptByHash = Object.fromEntries(
    broadcast.receipts.map(r => [r.transactionHash.toLowerCase(), r])
);

const transferTxs = broadcast.transactions.filter(tx => tx.function?.startsWith('transfer('));
const approvalTxs = broadcast.transactions.filter(tx => tx.function?.startsWith('approve('));



// ── Shared setup ──────────────────────────────────────────────────────────────

let client;
let eventRecords;
let transactions;

beforeAll(async () => {
    client = new Client(PG_OPTIONS);
    await client.connect();
    eventRecords = await selectEventRecords(client);
    transactions = await loadTransactions(TX_PATH);
}, 15_000);

afterAll(async () => {
    await client.end();
});

describe("Indexer", () => {
    test('Indexer: event_records match broadcast transactions', () => {
        expect(eventRecords.length).toBe(transactions.size);

        eventRecords.forEach(er => {
            const tx = transactions.get(er.tx_hash);
            expect(tx).toBeDefined();
            expect(er.contract_address).toBe(tx.contractAddress);
            expect(er.topic).toBe(getTopic(tx));
        });
    });


    describe('Indexer: GET /health', () => {
        test('returns 200', async () => {
            const res = await fetch(`${INDEXER_URL}/health`);
            expect(res.status).toBe(200);
        });
    });

// ── Indexer: GET /state ───────────────────────────────────────────────────────

    describe('Indexer: GET /state', () => {
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
                    'SELECT MAX(block_number) AS max FROM event_records WHERE topic = $1',
                    [topic]
                );
                const maxIndexed = Number(rows[0].max ?? 0);
                expect(lastBlock).toBeGreaterThanOrEqual(maxIndexed);
            }
        });
    });

// ── DB: event_records integrity ───────────────────────────────────────────────

    describe('DB: event_records integrity', () => {
        test('(tx_hash, log_index) is unique', async () => {
            const { rows } = await client.query(`
            SELECT COUNT(*) = COUNT(DISTINCT (tx_hash, log_index)) AS ok
            FROM event_records
        `);
            expect(rows[0].ok).toBe(true);
        });

        test('Transfer events exist for every contract address', async () => {
            for (const addr of contractAddresses) {
                const { rows } = await client.query(
                    'SELECT COUNT(*) FROM event_records WHERE topic = $1 AND contract_address = $2',
                    ['Transfer', addr]
                );
                expect(Number(rows[0].count)).toBeGreaterThan(0);
            }
        });

        test('Approval events exist for every contract address', async () => {
            for (const addr of contractAddresses) {
                const { rows } = await client.query(
                    'SELECT COUNT(*) FROM event_records WHERE topic = $1 AND contract_address = $2',
                    ['Approval', addr]
                );
                expect(Number(rows[0].count)).toBeGreaterThan(0);
            }
        });

        test('Transfer count >= generated transfer transactions', async () => {
            const { rows } = await client.query(
                'SELECT COUNT(*) FROM event_records WHERE topic = $1',
                ['Transfer']
            );
            // >= because Deploy mints also emit Transfer
            expect(Number(rows[0].count)).toBeGreaterThanOrEqual(transferTxs.length);
        });

        test('Approval count equals generated approval transactions', async () => {
            const { rows } = await client.query(
                'SELECT COUNT(*) FROM event_records WHERE topic = $1',
                ['Approval']
            );
            expect(Number(rows[0].count)).toBe(approvalTxs.length);
        });

        test('indexed tx_hashes include all GenerateEvents transfer hashes', async () => {
            const hashes = transferTxs.map(tx => tx.hash.toLowerCase());
            const { rows } = await client.query(
                'SELECT COUNT(*) FROM event_records WHERE topic = $1 AND tx_hash = ANY($2::text[])',
                ['Transfer', hashes]
            );
            expect(Number(rows[0].count)).toBeGreaterThanOrEqual(hashes.length);
        });
    });
});



describe("Api Server", () => {
    // ── Helpers ───────────────────────────────────────────────────────────────────
    async function search(topic, params = {}) {
        const entries = Object.entries(params).map(([k, v]) => [
            k,
            typeof v === 'object' ? JSON.stringify(v) : String(v),
        ]);
        const qs = new URLSearchParams(entries).toString();
        const url = `${API_URL}/search/${topic}${qs ? '?' + qs : ''}`;
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status} – ${await res.text()}`);
        return res.json();
    }

    describe('API: /health', () => {
        test('returns 200 OK', async () => {
            const res = await fetch(`${API_URL}/health`);
            expect(res.status).toBe(200);
            expect(await res.text()).toBe('OK');
        });
    });

    describe('API: unknown topic', () => {
        test('returns 404', async () => {
            const res = await fetch(`${API_URL}/search/NonExistentEvent`);
            expect(res.status).toBe(404);
        });
    });

    describe('API: Transfer – no filter', () => {
        let data;
        beforeAll(async () => { data = await search('Transfer'); });

        test('response has count and result array', () => {
            expect(typeof data.count).toBe('number');
            expect(Array.isArray(data.result)).toBe(true);
        });

        test('count matches result length', () => {
            expect(data.result).toHaveLength(data.count);
        });

        test('count >= generated transfer txs', () => {
            expect(data.count).toBeGreaterThanOrEqual(transferTxs.length);
        });

        test('every record has required fields', () => {
            for (const r of data.result) {
                expect(r).toHaveProperty('contract_address');
                expect(r).toHaveProperty('tx_hash');
                expect(r).toHaveProperty('block_hash');
                expect(r).toHaveProperty('block_number');
                expect(r).toHaveProperty('log_index');
                expect(r).toHaveProperty('data');
                expect(r).toHaveProperty('timestamp');
            }
        });

        test('Transfer data contains from / to / value', () => {
            for (const r of data.result) {
                expect(r.data).toHaveProperty('from');
                expect(r.data).toHaveProperty('to');
                expect(r.data).toHaveProperty('value');
            }
        });

        test('results are ordered by block_number ASC then log_index ASC', () => {
            for (let i = 1; i < data.result.length; i++) {
                const prev = data.result[i - 1];
                const curr = data.result[i];
                const cmp =
                    prev.block_number !== curr.block_number
                        ? prev.block_number - curr.block_number
                        : prev.log_index - curr.log_index;
                expect(cmp).toBeLessThanOrEqual(0);
            }
        });
    });

    describe('API: Approval – no filter', () => {
        let data;
        beforeAll(async () => { data = await search('Approval'); });

        test('count equals generated approval txs', () => {
            expect(data.count).toBe(approvalTxs.length);
        });

        test('Approval data contains owner / spender / value', () => {
            for (const r of data.result) {
                expect(r.data).toHaveProperty('owner');
                expect(r.data).toHaveProperty('spender');
                expect(r.data).toHaveProperty('value');
            }
        });
    });

    describe('API: filter by contract_address', () => {
        test('returns only records for the given address', async () => {
            const addr = contractAddresses[0];
            const data = await search('Transfer', { contract_address: addr });
            expect(data.count).toBeGreaterThan(0);
            for (const r of data.result) {
                expect(r.contract_address.toLowerCase()).toBe(addr);
            }
        });

        test('each contract address has the same total across the two tokens', async () => {
            const counts = await Promise.all(
                contractAddresses.map(addr =>
                    search('Transfer', { contract_address: addr }).then(d => d.count)
                )
            );
            // Both tokens receive the same number of transfers
            expect(counts[0]).toBe(counts[1]);
        });
    });

    describe('API: filter by tx_hash', () => {
        test('returns records matching the tx_hash', async () => {
            const txHash = transferTxs[0].hash.toLowerCase();
            const data = await search('Transfer', { tx_hash: txHash });
            expect(data.count).toBeGreaterThanOrEqual(1);
            for (const r of data.result) {
                expect(r.tx_hash.toLowerCase()).toBe(txHash);
            }
        });
    });

    describe('API: filter by block_number', () => {
        let minBlock;

        beforeAll(async () => {
            const firstReceipt = receiptByHash[transferTxs[0].hash.toLowerCase()];
            minBlock = parseInt(firstReceipt.blockNumber, 16);
        });

        test('gte filter excludes earlier blocks', async () => {
            const data = await search('Transfer', { block_number: { gte: minBlock } });
            expect(data.count).toBeGreaterThan(0);
            for (const r of data.result) {
                expect(r.block_number).toBeGreaterThanOrEqual(minBlock);
            }
        });

        test('lte filter excludes later blocks', async () => {
            const data = await search('Transfer', { block_number: { lte: minBlock } });
            for (const r of data.result) {
                expect(r.block_number).toBeLessThanOrEqual(minBlock);
            }
        });

        test('gte + lte range pins to a single block', async () => {
            const data = await search('Transfer', {
                block_number: { gte: minBlock, lte: minBlock },
            });
            for (const r of data.result) {
                expect(r.block_number).toBe(minBlock);
            }
        });

        test('empty range (gt max < min) returns zero results', async () => {
            const data = await search('Transfer', {
                block_number: { gt: minBlock, lt: minBlock },
            });
            expect(data.count).toBe(0);
        });
    });

    describe('API: pagination', () => {
        test('limit restricts result count', async () => {
            const limit = 5;
            const data = await search('Transfer', { limit });
            expect(data.result.length).toBeLessThanOrEqual(limit);
        });

        test('cursor advances the window without overlap', async () => {
            const page1 = await search('Transfer', { limit: 10 });
            expect(page1.result.length).toBe(10);

            const last = page1.result[page1.result.length - 1];
            const cursor = {
                block_number: last.block_number,
                log_index: last.log_index + 1,
            };
            const page2 = await search('Transfer', { limit: 10, cursor });

            const page1Keys = new Set(
                page1.result.map(r => `${r.tx_hash}:${r.log_index}`)
            );
            for (const r of page2.result) {
                expect(page1Keys.has(`${r.tx_hash}:${r.log_index}`)).toBe(false);
            }
        });

        test('limit=0 returns all results', async () => {
            const all  = await search('Transfer');
            const data = await search('Transfer', { limit: 0 });
            expect(data.count).toBe(all.count);
        });
    });
})
