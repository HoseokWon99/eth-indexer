import path from 'path';

export const DB_CONFIG = {
  host: process.env.POSTGRES_HOST ?? 'localhost',
  port: parseInt(process.env.POSTGRES_PORT ?? '5434'),
  database: process.env.POSTGRES_DB ?? 'eth_indexer_test',
  user: process.env.POSTGRES_USER ?? 'indexer',
  password: process.env.POSTGRES_PASSWORD ?? 'indexer_password',
};

export const API_BASE_URL = process.env.API_BASE_URL ?? 'http://localhost:8082';

export const BROADCAST_PATH =
  process.env.BROADCAST_PATH ??
  path.resolve(__dirname, '../contracts/broadcast/GenerateEvents.s.sol/31337/run-latest.json');