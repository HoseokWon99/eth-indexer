const { Client } = require('pg');
const fs = require('fs');
const { DB_CONFIG, BROADCAST_PATH } = require('./setup');

let txsByFunction;
let dbRows;

beforeAll(async () => {
  // Load broadcast JSON and partition by function name
  const broadcast = JSON.parse(fs.readFileSync(BROADCAST_PATH, 'utf8'));
  txsByFunction = {};
  for (const tx of broadcast.transactions) {
    const fn = tx.function ? tx.function.split('(')[0] : 'unknown';
    if (!txsByFunction[fn]) txsByFunction[fn] = [];
    txsByFunction[fn].push(tx);
  }

  // Query all event records from DB
  const client = new Client(DB_CONFIG);
  await client.connect();
  try {
    const res = await client.query('SELECT * FROM event_records');
    dbRows = res.rows;
  } finally {
    await client.end();
  }
});

test('Transfer tx hashes are indexed', () => {
  const transferTxs = txsByFunction['transfer'] || [];
  expect(transferTxs.length).toBeGreaterThan(0);

  const dbHashes = new Set(dbRows.map(r => r.tx_hash.toLowerCase()));
  const transferRows = dbRows.filter(r => r.event_name === 'Transfer');
  const transferHashes = new Set(transferRows.map(r => r.tx_hash.toLowerCase()));

  for (const tx of transferTxs) {
    const hash = tx.hash.toLowerCase();
    expect(transferHashes.has(hash) || dbHashes.has(hash)).toBe(true);
  }
});

test('Approval tx hashes are indexed', () => {
  const approveTxs = txsByFunction['approve'] || [];
  expect(approveTxs.length).toBeGreaterThan(0);

  const dbHashes = new Set(dbRows.map(r => r.tx_hash.toLowerCase()));
  const approvalRows = dbRows.filter(r => r.event_name === 'Approval');
  const approvalHashes = new Set(approvalRows.map(r => r.tx_hash.toLowerCase()));

  for (const tx of approveTxs) {
    const hash = tx.hash.toLowerCase();
    expect(approvalHashes.has(hash) || dbHashes.has(hash)).toBe(true);
  }
});

test('Transfer count is at least 122 (120 txs + 2 constructor mints)', () => {
  const transferRows = dbRows.filter(r => r.event_name === 'Transfer');
  expect(transferRows.length).toBeGreaterThanOrEqual(122);
});

test('Approval count is exactly 120', () => {
  const approvalRows = dbRows.filter(r => r.event_name === 'Approval');
  expect(approvalRows.length).toBe(120);
});
