/**
 * Anvil-specific test utilities
 */

const axios = require('axios');

const ANVIL_RPC_URL = process.env.ANVIL_RPC_URL || 'http://localhost:8545';
const INDEXER_API_URL = process.env.INDEXER_API_URL || 'http://localhost:8081';

/**
 * Anvil RPC client
 */
const anvilClient = axios.create({
  baseURL: ANVIL_RPC_URL,
  headers: { 'Content-Type': 'application/json' },
});

/**
 * Indexer API client
 */
const indexerClient = axios.create({
  baseURL: INDEXER_API_URL,
});

/**
 * Make a JSON-RPC call to Anvil
 */
async function rpcCall(method, params = []) {
  const response = await anvilClient.post('', {
    jsonrpc: '2.0',
    id: 1,
    method,
    params,
  });
  return response.data.result;
}

/**
 * Get current block number from Anvil
 */
async function getBlockNumber() {
  const blockNumHex = await rpcCall('eth_blockNumber');
  return parseInt(blockNumHex, 16);
}

/**
 * Mine blocks manually (advance chain)
 */
async function mineBlocks(count) {
  for (let i = 0; i < count; i++) {
    await rpcCall('evm_mine');
  }
}

/**
 * Get block by number
 */
async function getBlock(blockNumber) {
  const blockNumHex = `0x${blockNumber.toString(16)}`;
  return await rpcCall('eth_getBlockByNumber', [blockNumHex, true]);
}

/**
 * Wait for indexer to catch up to a specific block
 */
async function waitForIndexerSync(targetBlock, timeoutMs = 30000) {
  const startTime = Date.now();
  while (Date.now() - startTime < timeoutMs) {
    try {
      const response = await indexerClient.get('/health');
      const currentBlock = response.data.currentBlock || 0;

      if (currentBlock >= targetBlock) {
        return true;
      }
    } catch (error) {
      // Indexer might not be ready yet
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`Indexer did not sync to block ${targetBlock} within ${timeoutMs}ms`);
}

/**
 * Get indexer health status
 */
async function getIndexerHealth() {
  const response = await indexerClient.get('/health');
  return response.data;
}

/**
 * Search for events via indexer API
 */
async function searchEvents(eventName, filters = {}) {
  const response = await indexerClient.post(`/search/${eventName}`, filters);
  return response.data;
}

module.exports = {
  anvilClient,
  indexerClient,
  rpcCall,
  getBlockNumber,
  mineBlocks,
  getBlock,
  waitForIndexerSync,
  getIndexerHealth,
  searchEvents,
  ANVIL_RPC_URL,
  INDEXER_API_URL,
};
