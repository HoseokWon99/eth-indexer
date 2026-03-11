const { describe, test, expect, beforeAll } = require('@jest/globals');

let sampleEvent = null;

beforeAll(async () => {
  // Get a sample event to use for filter tests
  const response = await api.get('/search/Transfer');
  if (response.data.result.length > 0) {
    sampleEvent = response.data.result[0];
  }
});

describe('Filter Tests', () => {
  describe('Contract Address Filter', () => {
    test('should filter by single contract address', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          contract_address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
        }
      });

      expect(response.status).toBe(200);
      expect(response.data).toHaveProperty('count');
      expect(response.data).toHaveProperty('result');

      // All results should be from the specified contract
      response.data.result.forEach(event => {
        expect(event.contract_address.toLowerCase())
          .toBe('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'.toLowerCase());
      });
    });

    test('should filter by multiple contract addresses', async () => {
      const addresses = [
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        '0xdAC17F958D2ee523a2206206994597C13D831ec7'
      ];

      const response = await api.get('/search/Transfer', {
        params: {
          contract_address: addresses.join(',')
        }
      });

      expect(response.status).toBe(200);

      // All results should be from one of the specified contracts
      response.data.result.forEach(event => {
        const match = addresses.some(addr =>
          event.contract_address.toLowerCase() === addr.toLowerCase()
        );
        expect(match).toBe(true);
      });
    });

    test('should return empty result for non-existent contract', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          contract_address: '0x0000000000000000000000000000000000000001'
        }
      });

      expect(response.status).toBe(200);
      expect(response.data.count).toBe(0);
      expect(response.data.result).toEqual([]);
    });
  });

  describe('Block Number Filters', () => {
    test('should filter by block_number gte (greater than or equal)', async () => {
      const blockNumber = 24633120;
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gte: blockNumber })
        }
      });

      expect(response.status).toBe(200);

      // All results should have block_number >= specified value
      response.data.result.forEach(event => {
        expect(event.block_number).toBeGreaterThanOrEqual(blockNumber);
      });
    });

    test('should filter by block_number lte (less than or equal)', async () => {
      const blockNumber = 24633130;
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ lte: blockNumber })
        }
      });

      expect(response.status).toBe(200);

      // All results should have block_number <= specified value
      response.data.result.forEach(event => {
        expect(event.block_number).toBeLessThanOrEqual(blockNumber);
      });
    });

    test('should filter by block_number range (gte + lte)', async () => {
      const minBlock = 24633120;
      const maxBlock = 24633130;

      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gte: minBlock, lte: maxBlock })
        }
      });

      expect(response.status).toBe(200);

      // All results should be within the range
      response.data.result.forEach(event => {
        expect(event.block_number).toBeGreaterThanOrEqual(minBlock);
        expect(event.block_number).toBeLessThanOrEqual(maxBlock);
      });
    });

    test('should filter by exact block_number (eq)', async () => {
      if (!sampleEvent) {
        return; // Skip if no sample data
      }

      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ eq: sampleEvent.block_number })
        }
      });

      expect(response.status).toBe(200);

      // All results should have the exact block number
      response.data.result.forEach(event => {
        expect(event.block_number).toBe(sampleEvent.block_number);
      });
    });

    test('should filter by block_number gt (greater than)', async () => {
      const blockNumber = 24633120;
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ gt: blockNumber })
        }
      });

      expect(response.status).toBe(200);

      // All results should have block_number > specified value
      response.data.result.forEach(event => {
        expect(event.block_number).toBeGreaterThan(blockNumber);
      });
    });

    test('should filter by block_number lt (less than)', async () => {
      const blockNumber = 24633130;
      const response = await api.get('/search/Transfer', {
        params: {
          block_number: JSON.stringify({ lt: blockNumber })
        }
      });

      expect(response.status).toBe(200);

      // All results should have block_number < specified value
      response.data.result.forEach(event => {
        expect(event.block_number).toBeLessThan(blockNumber);
      });
    });
  });

  describe('Transaction Hash Filter', () => {
    test('should filter by tx_hash', async () => {
      if (!sampleEvent) {
        return; // Skip if no sample data
      }

      const response = await api.get('/search/Transfer', {
        params: {
          tx_hash: sampleEvent.tx_hash
        }
      });

      expect(response.status).toBe(200);
      expect(response.data.count).toBeGreaterThanOrEqual(1);

      // All results should have the specified tx_hash
      response.data.result.forEach(event => {
        expect(event.tx_hash).toBe(sampleEvent.tx_hash);
      });
    });

    test('should return empty for non-existent tx_hash', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          tx_hash: '0x0000000000000000000000000000000000000000000000000000000000000000'
        }
      });

      expect(response.status).toBe(200);
      expect(response.data.count).toBe(0);
      expect(response.data.result).toEqual([]);
    });
  });

  describe('Block Hash Filter', () => {
    test('should filter by block_hash', async () => {
      if (!sampleEvent) {
        return; // Skip if no sample data
      }

      const response = await api.get('/search/Transfer', {
        params: {
          block_hash: sampleEvent.block_hash
        }
      });

      expect(response.status).toBe(200);

      // All results should have the specified block_hash
      response.data.result.forEach(event => {
        expect(event.block_hash).toBe(sampleEvent.block_hash);
      });
    });
  });

  describe('Log Index Filter', () => {
    test('should filter by single log_index', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          log_index: '0'
        }
      });

      expect(response.status).toBe(200);

      // All results should have log_index = 0
      response.data.result.forEach(event => {
        expect(event.log_index).toBe(0);
      });
    });

    test('should filter by multiple log_index values', async () => {
      const response = await api.get('/search/Transfer', {
        params: {
          log_index: '0,1,2'
        }
      });

      expect(response.status).toBe(200);

      // All results should have log_index in [0, 1, 2]
      response.data.result.forEach(event => {
        expect([0, 1, 2]).toContain(event.log_index);
      });
    });
  });

  describe('Combined Filters', () => {
    test('should support multiple filters together', async () => {
      const minBlock = 24633120;
      const maxBlock = 24633130;
      const contractAddress = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';

      const response = await api.get('/search/Transfer', {
        params: {
          contract_address: contractAddress,
          block_number: JSON.stringify({ gte: minBlock, lte: maxBlock }),
          log_index: '0'
        }
      });

      expect(response.status).toBe(200);

      // All results should match ALL filters
      response.data.result.forEach(event => {
        expect(event.contract_address.toLowerCase()).toBe(contractAddress.toLowerCase());
        expect(event.block_number).toBeGreaterThanOrEqual(minBlock);
        expect(event.block_number).toBeLessThanOrEqual(maxBlock);
        expect(event.log_index).toBe(0);
      });
    });
  });
});
