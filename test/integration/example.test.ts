import { Client } from 'pg';
import { DB_CONFIG } from './setup';

describe('Indexing', () => {
  let client: Client;

  beforeAll(async () => {
    client = new Client(DB_CONFIG);
    await client.connect();
  });

  afterAll(async () => {
    await client.end();
  });

  it('connects to PostgreSQL', async () => {
    const res = await client.query<{ now: Date }>('SELECT NOW() AS now');
    expect(res.rows[0].now).toBeInstanceOf(Date);
  });
});