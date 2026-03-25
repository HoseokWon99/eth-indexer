const fetch = require('node-fetch');
const { INDEXER_BASE_URL } = require('./setup');

test('GET /state returns 200 with Transfer and Approval block numbers > 0', async () => {
  const res = await fetch(`${INDEXER_BASE_URL}/state`);
  expect(res.status).toBe(200);
  const data = await res.json();
  expect(typeof data['Transfer']).toBe('number');
  expect(typeof data['Approval']).toBe('number');
  expect(data['Transfer']).toBeGreaterThan(0);
  expect(data['Approval']).toBeGreaterThan(0);
});

test('GET /health returns 200', async () => {
  const res = await fetch(`${INDEXER_BASE_URL}/health`);
  expect(res.status).toBe(200);
});
