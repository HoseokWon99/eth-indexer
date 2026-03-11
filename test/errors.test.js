const { describe, test, expect } = require('@jest/globals');

describe('Error Handling', () => {
  describe('Invalid Topics', () => {
    test('should return 404 for non-existent topic', async () => {
      const response = await api.get('/search/InvalidEvent');
      expect(response.status).toBe(404);
    });

    test('should return error message for invalid topic', async () => {
      const response = await api.get('/search/InvalidEvent');
      expect(response.data).toContain('Topic Not Found');
    });

    test('should return 404 for empty topic', async () => {
      const response = await api.get('/search/');
      expect(response.status).toBe(404);
    });

    test('should return 404 for random topic names', async () => {
      const invalidTopics = ['RandomEvent', 'Swap', 'Mint', 'Burn'];

      for (const topic of invalidTopics) {
        const response = await api.get(`/search/${topic}`);
        expect(response.status).toBe(404);
      }
    });
  });

  describe('Invalid Filter Parameters', () => {
    test('should return 400 for invalid block_number format', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: 'invalid'
        }
      });

      expect(response.status).toBe(400);
      expect(response.data).toContain('Invalid query parameters');
    });

    test('should return 400 for malformed block_number JSON', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: '{invalid json}'
        }
      });

      expect(response.status).toBe(400);
      expect(response.data).toContain('Invalid query parameters');
    });

    test('should return 400 for invalid log_index format', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          log_index: 'abc'
        }
      });

      expect(response.status).toBe(400);
      expect(response.data).toContain('Invalid query parameters');
    });

    test('should return 400 for negative log_index', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          log_index: '-1'
        }
      });

      expect(response.status).toBe(400);
    });
  });

  describe('Invalid Endpoints', () => {
    test('should return 404 for non-existent endpoint', async () => {
      const response = await api.get('/nonexistent');
      expect(response.status).toBe(404);
    });

    test('should return 404 for /api endpoint', async () => {
      const response = await api.get('/api');
      expect(response.status).toBe(404);
    });

    test('should return 404 for /events endpoint', async () => {
      const response = await api.get('/events');
      expect(response.status).toBe(404);
    });
  });

  describe('HTTP Methods', () => {
    test('should support GET on /search/{topic}', async () => {
      const response = await api.get('/search/Transfer');
      expect(response.status).toBe(200);
    });

    test('should reject POST on /search/{topic}', async () => {
      const response = await api.post('/search/Transfer');
      expect(response.status).toBe(405);
    });

    test('should reject PUT on /search/{topic}', async () => {
      const response = await api.put('/search/Transfer');
      expect(response.status).toBe(405);
    });

    test('should reject DELETE on /search/{topic}', async () => {
      const response = await api.delete('/search/Transfer');
      expect(response.status).toBe(405);
    });
  });

  describe('Edge Cases', () => {
    test('should handle very large block_number values', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gte: 999999999999 })
        }
      });

      expect(response.status).toBe(200);
      expect(response.data.count).toBe(0);
      expect(response.data.result).toEqual([]);
    });

    test('should handle block range with gte > lte', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gte: 1000, lte: 100 })
        }
      });

      expect(response.status).toBe(200);
      expect(response.data.count).toBe(0);
      expect(response.data.result).toEqual([]);
    });

    test('should handle empty contract_address parameter', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          contract_address: ''
        }
      });

      expect(response.status).toBe(200);
    });

    test('should handle case-insensitive contract addresses', async () => {
      const upperCase = await api.get('/search/Transfer', {
        params: {
          contract_address: '0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48'
        }
      });

      const lowerCase = await api.get('/search/Transfer', {
        params: {
          contract_address: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48'
        }
      });

      expect(upperCase.status).toBe(200);
      expect(lowerCase.status).toBe(200);
    });
  });
});
