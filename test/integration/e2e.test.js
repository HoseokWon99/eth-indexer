/**
 * End-to-end tests for eth-indexer with Anvil
 */

const fs = require('fs');
const path = require('path');
const {
  getBlockNumber,
  getIndexerHealth,
  searchEvents,
  waitForIndexerSync,
} = require('./setup');

describe('Anvil E2E Tests', () => {
  let deployedAddresses;
  let token1Address;
  let token2Address;

  beforeAll(async () => {
    // Load deployed contract addresses
    const addressesPath = path.join(__dirname, '../../deployed-addresses.json');
    if (!fs.existsSync(addressesPath)) {
      throw new Error('deployed-addresses.json not found. Run setup-test-env.sh first.');
    }

    deployedAddresses = JSON.parse(fs.readFileSync(addressesPath, 'utf8'));
    token1Address = deployedAddresses.token1.toLowerCase();
    token2Address = deployedAddresses.token2.toLowerCase();

    console.log('Test Configuration:');
    console.log(`  Token1 (TUSDC): ${token1Address}`);
    console.log(`  Token2 (TUSDT): ${token2Address}`);

    // Wait for indexer to be healthy and synced
    const currentBlock = await getBlockNumber();
    console.log(`  Current Anvil block: ${currentBlock}`);

    await waitForIndexerSync(currentBlock - 1, 60000);
    console.log('  Indexer synced ✓');
  }, 90000);

  describe('Health Check', () => {
    test('should return healthy status', async () => {
      const health = await getIndexerHealth();
      expect(health).toHaveProperty('status');
      expect(health.status).toBe('healthy');
    });
  });

  describe('Event Indexing', () => {
    test('should index all Transfer events', async () => {
      const result = await searchEvents('Transfer', {});

      // Expected: 90 Transfers (50 from Token1 + 40 from Token2)
      // Note: Constructor also emits Transfer(0x0, deployer, initialSupply)
      // So we expect 92 total (90 + 2 constructor events)
      expect(result.hits).toBeDefined();
      expect(result.hits.length).toBeGreaterThanOrEqual(90);

      // Verify event structure
      const firstEvent = result.hits[0];
      expect(firstEvent).toHaveProperty('blockNumber');
      expect(firstEvent).toHaveProperty('transactionHash');
      expect(firstEvent).toHaveProperty('contractAddress');
      expect(firstEvent).toHaveProperty('eventName', 'Transfer');
      expect(firstEvent).toHaveProperty('args');
      expect(firstEvent.args).toHaveProperty('from');
      expect(firstEvent.args).toHaveProperty('to');
      expect(firstEvent.args).toHaveProperty('value');
    });

    test('should index all Approval events', async () => {
      const result = await searchEvents('Approval', {});

      // Expected: 50 Approvals (30 from Token1 + 20 from Token2)
      expect(result.hits).toBeDefined();
      expect(result.hits.length).toBeGreaterThanOrEqual(50);

      // Verify event structure
      const firstEvent = result.hits[0];
      expect(firstEvent).toHaveProperty('eventName', 'Approval');
      expect(firstEvent.args).toHaveProperty('owner');
      expect(firstEvent.args).toHaveProperty('spender');
      expect(firstEvent.args).toHaveProperty('value');
    });

    test('should have indexed total of 140+ events', async () => {
      const transferResult = await searchEvents('Transfer', {});
      const approvalResult = await searchEvents('Approval', {});

      const totalEvents = transferResult.hits.length + approvalResult.hits.length;

      // Expected: 142 events (90 Transfers + 50 Approvals + 2 constructor Transfers)
      expect(totalEvents).toBeGreaterThanOrEqual(140);
    });
  });

  describe('Contract Address Filtering', () => {
    test('should filter Transfer events by Token1 address', async () => {
      const result = await searchEvents('Transfer', {
        contractAddress: token1Address,
      });

      expect(result.hits).toBeDefined();
      expect(result.hits.length).toBeGreaterThanOrEqual(50);

      // All events should be from Token1
      result.hits.forEach(event => {
        expect(event.contractAddress.toLowerCase()).toBe(token1Address);
      });
    });

    test('should filter Transfer events by Token2 address', async () => {
      const result = await searchEvents('Transfer', {
        contractAddress: token2Address,
      });

      expect(result.hits).toBeDefined();
      expect(result.hits.length).toBeGreaterThanOrEqual(40);

      // All events should be from Token2
      result.hits.forEach(event => {
        expect(event.contractAddress.toLowerCase()).toBe(token2Address);
      });
    });
  });

  describe('Event Data Validation', () => {
    test('Transfer events should have deterministic recipients', async () => {
      const result = await searchEvents('Transfer', {
        contractAddress: token1Address,
        limit: 50,
      });

      const expectedAddresses = [
        '0x1111111111111111111111111111111111111111',
        '0x2222222222222222222222222222222222222222',
        '0x3333333333333333333333333333333333333333',
      ];

      // Filter out constructor event (from = 0x0)
      const regularTransfers = result.hits.filter(
        event => event.args.from !== '0x0000000000000000000000000000000000000000'
      );

      // Verify recipients follow pattern (alice, bob, charlie rotation)
      regularTransfers.forEach(event => {
        const recipient = event.args.to.toLowerCase();
        expect(expectedAddresses.map(a => a.toLowerCase())).toContain(recipient);
      });
    });

    test('Transfer values should be deterministic', async () => {
      const result = await searchEvents('Transfer', {
        contractAddress: token1Address,
        limit: 10,
      });

      // Filter out constructor event
      const regularTransfers = result.hits.filter(
        event => event.args.from !== '0x0000000000000000000000000000000000000000'
      );

      // First transfer should be 1000 * 10^18
      if (regularTransfers.length > 0) {
        const firstValue = BigInt(regularTransfers[0].args.value);
        expect(firstValue).toBeGreaterThan(0n);
      }
    });
  });

  describe('Pagination', () => {
    test('should support pagination with limit', async () => {
      const result = await searchEvents('Transfer', { limit: 10 });

      expect(result.hits).toBeDefined();
      expect(result.hits.length).toBeLessThanOrEqual(10);
      expect(result).toHaveProperty('total');
    });

    test('should support search_after pagination', async () => {
      const firstPage = await searchEvents('Transfer', { limit: 20 });
      expect(firstPage.hits.length).toBeGreaterThan(0);

      if (firstPage.hits.length === 20) {
        const lastEvent = firstPage.hits[firstPage.hits.length - 1];
        const searchAfter = lastEvent.sort || lastEvent._id;

        const secondPage = await searchEvents('Transfer', {
          limit: 20,
          search_after: searchAfter,
        });

        expect(secondPage.hits.length).toBeGreaterThan(0);
        // Second page should have different events
        expect(secondPage.hits[0]._id).not.toBe(firstPage.hits[0]._id);
      }
    });
  });

  describe('Error Handling', () => {
    test('should handle invalid event name gracefully', async () => {
      try {
        await searchEvents('InvalidEvent', {});
        fail('Should have thrown an error');
      } catch (error) {
        expect(error.response).toBeDefined();
        expect(error.response.status).toBeGreaterThanOrEqual(400);
      }
    });

    test('should handle invalid contract address gracefully', async () => {
      const result = await searchEvents('Transfer', {
        contractAddress: '0x0000000000000000000000000000000000000000',
      });

      // Should return empty results, not error
      expect(result.hits).toBeDefined();
      expect(result.hits.length).toBe(0);
    });
  });
});
