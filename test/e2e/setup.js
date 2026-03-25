const path = require('path');

const DB_CONFIG = {
  host: process.env.POSTGRES_HOST || 'localhost',
  port: parseInt(process.env.POSTGRES_PORT || '5434'),
  database: process.env.POSTGRES_DB || 'eth_indexer_test',
  user: process.env.POSTGRES_USER || 'indexer',
  password: process.env.POSTGRES_PASSWORD || 'indexer_password',
};

const API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:8082';
const INDEXER_BASE_URL = process.env.INDEXER_BASE_URL || 'http://localhost:8081';

// Works both on host (test/e2e/ -> test/contracts/) and in container (mount: ./test:/app -> /app/contracts/)
const BROADCAST_PATH = process.env.BROADCAST_PATH ||
  path.resolve(__dirname, '../contracts/broadcast/GenerateEvents.s.sol/31337/run-latest.json');

async function apiGet(fetchFn, basePath, urlPath, params) {
  const url = new URL(urlPath, basePath);
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }
  }
  const res = await fetchFn(url.toString());
  if (!res.ok) {
    const body = await res.text();
    throw Object.assign(new Error(`HTTP ${res.status}: ${body}`), { status: res.status });
  }
  return res.json();
}

module.exports = { DB_CONFIG, API_BASE_URL, INDEXER_BASE_URL, apiGet, BROADCAST_PATH };
