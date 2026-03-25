const fetch = require('node-fetch');
const { Client } = require('pg');
const { DB_CONFIG, API_BASE_URL, apiGet } = require('./setup');

let dbTransferRows;
let dbApprovalRows;

beforeAll(async () => {
  const client = new Client(DB_CONFIG);
  await client.connect();
  try {
    const t = await client.query("SELECT * FROM event_records WHERE event_name = 'Transfer' ORDER BY block_number, log_index LIMIT 10");
    dbTransferRows = t.rows;
    const a = await client.query("SELECT * FROM event_records WHERE event_name = 'Approval' ORDER BY block_number, log_index LIMIT 10");
    dbApprovalRows = a.rows;
  } finally {
    await client.end();
  }
});

function get(path, params) {
  return apiGet(fetch, API_BASE_URL, path, params);
}

test('GET /search/Transfer returns correct response shape', async () => {
  const data = await get('/search/Transfer');
  expect(typeof data.count).toBe('number');
  expect(Array.isArray(data.result)).toBe(true);
  if (data.result.length > 0) {
    const item = data.result[0];
    expect(item).toHaveProperty('contract_address');
    expect(item).toHaveProperty('tx_hash');
    expect(item).toHaveProperty('block_hash');
    expect(item).toHaveProperty('block_number');
    expect(item).toHaveProperty('log_index');
    expect(item).toHaveProperty('data');
    expect(item).toHaveProperty('timestamp');
  }
});

test('GET /search/UnknownTopic returns 404', async () => {
  let err;
  try {
    await get('/search/UnknownTopic');
  } catch (e) {
    err = e;
  }
  expect(err).toBeDefined();
  expect(err.status).toBe(404);
});

test('GET /search/Transfer with tx_hash filter returns matching rows', async () => {
  if (!dbTransferRows || dbTransferRows.length === 0) return;
  const txHash = dbTransferRows[0].tx_hash;
  const data = await get('/search/Transfer', { tx_hash: txHash });
  expect(data.count).toBeGreaterThan(0);
  for (const row of data.result) {
    expect(row.tx_hash.toLowerCase()).toBe(txHash.toLowerCase());
  }
});

test('GET /search/Transfer with block_number filter returns matching rows', async () => {
  if (!dbTransferRows || dbTransferRows.length === 0) return;
  const blockNumber = dbTransferRows[0].block_number;
  const data = await get('/search/Transfer', { 'block_number[eq]': blockNumber });
  expect(data.count).toBeGreaterThan(0);
  for (const row of data.result) {
    expect(Number(row.block_number)).toBe(Number(blockNumber));
  }
});

test('GET /search/Transfer with block_number gte/lte filter returns rows in range', async () => {
  if (!dbTransferRows || dbTransferRows.length < 2) return;
  const minBlock = dbTransferRows[0].block_number;
  const maxBlock = dbTransferRows[dbTransferRows.length - 1].block_number;
  const data = await get('/search/Transfer', {
    'block_number[gte]': minBlock,
    'block_number[lte]': maxBlock,
  });
  expect(data.count).toBeGreaterThan(0);
  for (const row of data.result) {
    expect(Number(row.block_number)).toBeGreaterThanOrEqual(Number(minBlock));
    expect(Number(row.block_number)).toBeLessThanOrEqual(Number(maxBlock));
  }
});

test('GET /search/Approval with contract_address filter returns rows for that address', async () => {
  if (!dbApprovalRows || dbApprovalRows.length === 0) return;
  const addr = dbApprovalRows[0].contract_address;
  const data = await get('/search/Approval', { contract_address: addr });
  expect(data.count).toBeGreaterThan(0);
  for (const row of data.result) {
    expect(row.contract_address.toLowerCase()).toBe(addr.toLowerCase());
  }
});

test('Pagination: limit and cursor work correctly', async () => {
  const page1 = await get('/search/Transfer', { limit: '5' });
  expect(page1.result.length).toBeLessThanOrEqual(5);

  if (page1.result.length === 5) {
    const last = page1.result[page1.result.length - 1];
    const cursor = JSON.stringify({ block_number: last.block_number, log_index: last.log_index });
    const page2 = await get('/search/Transfer', { limit: '5', cursor });
    expect(Array.isArray(page2.result)).toBe(true);
    if (page2.result.length > 0) {
      // First item of page2 should not duplicate last item of page1
      const page1Hashes = new Set(page1.result.map(r => `${r.tx_hash}-${r.log_index}`));
      for (const row of page2.result) {
        expect(page1Hashes.has(`${row.tx_hash}-${row.log_index}`)).toBe(false);
      }
    }
  }
});
