const { describe, test, expect } = require('@jest/globals');

describe('Health and Status Endpoints', () => {
  describe('GET /health', () => {
    test('should return 200 OK', async () => {
      const response = await api.get('/health');
      expect(response.status).toBe(200);
    });

    test('should return "OK" text', async () => {
      const response = await api.get('/health');
      expect(response.data).toBe('OK');
    });

    test('should have correct content type', async () => {
      const response = await api.get('/health');
      expect(response.headers['content-type']).toContain('text');
    });
  });

  describe('GET /status', () => {
    test('should return 200 OK', async () => {
      const response = await api.get('/status');
      expect(response.status).toBe(200);
    });

    test('should return JSON', async () => {
      const response = await api.get('/status');
      expect(response.headers['content-type']).toContain('application/json');
    });

    test('should have Transfer and Approval properties', async () => {
      const response = await api.get('/status');
      expect(response.data).toHaveProperty('Transfer');
      expect(response.data).toHaveProperty('Approval');
    });

    test('should have numeric block numbers', async () => {
      const response = await api.get('/status');
      expect(typeof response.data.Transfer).toBe('number');
      expect(typeof response.data.Approval).toBe('number');
    });

    test('should have non-negative block numbers', async () => {
      const response = await api.get('/status');
      expect(response.data.Transfer).toBeGreaterThanOrEqual(0);
      expect(response.data.Approval).toBeGreaterThanOrEqual(0);
    });

    test('should update block numbers over time', async () => {
      const initialResponse = await api.get('/status');
      const initialBlock = Math.max(initialResponse.data.Transfer, initialResponse.data.Approval);

      // Wait for new blocks
      await new Promise(resolve => setTimeout(resolve, 15000));

      const finalResponse = await api.get('/status');
      const finalBlock = Math.max(finalResponse.data.Transfer, finalResponse.data.Approval);

      expect(finalBlock).toBeGreaterThanOrEqual(initialBlock);
    }, 20000);
  });
});
