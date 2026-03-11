const { describe, test, expect } = require('@jest/globals');

describe('Search Endpoints', () => {
  describe('GET /search/Transfer', () => {
    test('should return 200 OK', async () => {
      const response = await api.get('/search/Transfer');
      expect(response.status).toBe(200);
    });

    test('should return JSON', async () => {
      const response = await api.get('/search/Transfer');
      expect(response.headers['content-type']).toContain('application/json');
    });

    test('should have count and result properties', async () => {
      const response = await api.get('/search/Transfer');
      expect(response.data).toHaveProperty('count');
      expect(response.data).toHaveProperty('result');
    });

    test('should have result as an array', async () => {
      const response = await api.get('/search/Transfer');
      expect(Array.isArray(response.data.result)).toBe(true);
    });

    test('should have count matching result length', async () => {
      const response = await api.get('/search/Transfer');
      expect(response.data.count).toBe(response.data.result.length);
    });

    test('should have events with required fields', async () => {
      const response = await api.get('/search/Transfer');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        expect(event).toHaveProperty('contract_address');
        expect(event).toHaveProperty('tx_hash');
        expect(event).toHaveProperty('block_hash');
        expect(event).toHaveProperty('block_number');
        expect(event).toHaveProperty('log_index');
        expect(event).toHaveProperty('data');
        expect(event).toHaveProperty('timestamp');
      }
    });

    test('should have Transfer event data structure (from, to, value)', async () => {
      const response = await api.get('/search/Transfer');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        expect(event.data).toHaveProperty('from');
        expect(event.data).toHaveProperty('to');
        expect(event.data).toHaveProperty('value');
      }
    });

    test('should have valid Ethereum addresses', async () => {
      const response = await api.get('/search/Transfer');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        // Contract address should be 40 hex chars (20 bytes)
        expect(event.contract_address).toMatch(/^0x[a-fA-F0-9]{40}$/);
        // Data addresses may be padded to 64 hex chars (32 bytes) - accept both formats
        expect(event.data.from).toMatch(/^0x[a-fA-F0-9]{40,66}$/);
        expect(event.data.to).toMatch(/^0x[a-fA-F0-9]{40,66}$/);
      }
    });

    test('should have valid transaction hash', async () => {
      const response = await api.get('/search/Transfer');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        expect(event.tx_hash).toMatch(/^0x[a-fA-F0-9]{64}$/);
      }
    });

    test('should have valid block hash', async () => {
      const response = await api.get('/search/Transfer');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        expect(event.block_hash).toMatch(/^0x[a-fA-F0-9]{64}$/);
      }
    });

    test('should have valid ISO timestamp', async () => {
      const response = await api.get('/search/Transfer');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        const timestamp = new Date(event.timestamp);
        expect(timestamp).toBeInstanceOf(Date);
        // Timestamp should be valid ISO 8601 format
        expect(event.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/);
        expect(isNaN(timestamp.getTime())).toBe(false);
      }
    });
  });

  describe('GET /search/Approval', () => {
    test('should return 200 OK', async () => {
      const response = await api.get('/search/Approval');
      expect(response.status).toBe(200);
    });

    test('should have count and result properties', async () => {
      const response = await api.get('/search/Approval');
      expect(response.data).toHaveProperty('count');
      expect(response.data).toHaveProperty('result');
    });

    test('should have Approval event data structure (owner, spender, value)', async () => {
      const response = await api.get('/search/Approval');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        expect(event.data).toHaveProperty('owner');
        expect(event.data).toHaveProperty('spender');
        expect(event.data).toHaveProperty('value');
      }
    });

    test('should have valid Ethereum addresses', async () => {
      const response = await api.get('/search/Approval');
      if (response.data.result.length > 0) {
        const event = response.data.result[0];
        // Data addresses may be padded to 64 hex chars (32 bytes) - accept both formats
        expect(event.data.owner).toMatch(/^0x[a-fA-F0-9]{40,66}$/);
        expect(event.data.spender).toMatch(/^0x[a-fA-F0-9]{40,66}$/);
      }
    });
  });

  describe('Response consistency', () => {
    test('should return same count on multiple requests', async () => {
      const response1 = await api.get('/search/Transfer');
      const response2 = await api.get('/search/Transfer');

      // Count might differ by a small amount due to real-time indexing
      const diff = Math.abs(response1.data.count - response2.data.count);
      expect(diff).toBeLessThanOrEqual(5);
    });
  });
});
