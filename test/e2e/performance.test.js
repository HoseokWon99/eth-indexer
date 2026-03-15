const { describe, test, expect } = require('@jest/globals');

describe('Performance Tests', () => {
  describe('Response Time', () => {
    test('health endpoint should respond within 100ms', async () => {
      const start = Date.now();
      await api.get('/health');
      const duration = Date.now() - start;

      expect(duration).toBeLessThan(100);
    });

    test('status endpoint should respond within 100ms', async () => {
      const start = Date.now();
      await api.get('/status');
      const duration = Date.now() - start;

      expect(duration).toBeLessThan(100);
    });

    test('search endpoint should respond within 500ms', async () => {
      const start = Date.now();
      await api.get('/search/Transfer');
      const duration = Date.now() - start;

      expect(duration).toBeLessThan(500);
    });

    test('filtered search should respond within 500ms', async () => {
      const start = Date.now();
      await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gte: 24633120 })
        }
      });
      const duration = Date.now() - start;

      expect(duration).toBeLessThan(500);
    });
  });

  describe('Concurrent Requests', () => {
    test('should handle 10 concurrent requests', async () => {
      const requests = Array(10).fill().map(() =>
        api.get('/search/Transfer')
      );

      const responses = await Promise.all(requests);

      responses.forEach(response => {
        expect(response.status).toBe(200);
        expect(response.data).toHaveProperty('count');
        expect(response.data).toHaveProperty('result');
      });
    });

    test('should handle concurrent requests to different topics', async () => {
      const requests = [
        api.get('/search/Transfer'),
        api.get('/search/Approval'),
        api.get('/search/Transfer'),
        api.get('/search/Approval'),
        api.get('/status'),
        api.get('/health')
      ];

      const responses = await Promise.all(requests);

      expect(responses[0].status).toBe(200);
      expect(responses[1].status).toBe(200);
      expect(responses[4].status).toBe(200);
      expect(responses[5].status).toBe(200);
    });
  });

  describe('Large Result Sets', () => {
    test('should handle requests with many results', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gte: 1 })
        }
      });

      expect(response.status).toBe(200);
      expect(response.data.count).toBeGreaterThanOrEqual(0);
      expect(Array.isArray(response.data.result)).toBe(true);
    });
  });

  describe('Response Time Consistency', () => {
    test('should have consistent response times across multiple requests', async () => {
      const iterations = 5;
      const times = [];

      for (let i = 0; i < iterations; i++) {
        const start = Date.now();
        await api.get('/search/Transfer');
        times.push(Date.now() - start);
      }

      const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
      const maxTime = Math.max(...times);
      const minTime = Math.min(...times);

      // Max time should not be more than 5x the min time
      expect(maxTime).toBeLessThan(minTime * 5);

      // Average should be reasonable
      expect(avgTime).toBeLessThan(500);
    });
  });

  describe('API Availability', () => {
    test('should maintain availability under load', async () => {
      const requests = Array(20).fill().map((_, i) =>
        api.get('/search/Transfer', {
          params: {
            block_number: JSON.stringify({ gte: 24633100 + i })
          }
        })
      );

      const responses = await Promise.all(requests);
      const successCount = responses.filter(r => r.status === 200).length;

      // All requests should succeed
      expect(successCount).toBe(20);
    });
  });

  describe('Memory and Resource Usage', () => {
    test('should not degrade performance over repeated requests', async () => {
      const iterations = 10;
      const times = [];

      for (let i = 0; i < iterations; i++) {
        const start = Date.now();
        await api.get('/search/Transfer');
        times.push(Date.now() - start);
      }

      // First and last request should have similar response times
      const firstHalf = times.slice(0, 5).reduce((a, b) => a + b, 0) / 5;
      const secondHalf = times.slice(5).reduce((a, b) => a + b, 0) / 5;

      // Second half should not be significantly slower (allow 2x variance)
      expect(secondHalf).toBeLessThan(firstHalf * 2);
    });
  });
});
