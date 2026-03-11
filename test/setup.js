const axios = require('axios');

// Global test configuration
global.API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:8080';

// Global axios instance
global.api = axios.create({
  baseURL: global.API_BASE_URL,
  timeout: 10000,
  validateStatus: () => true // Don't throw on any status
});

// Test utilities
global.testUtils = {
  // Wait for a condition to be true
  waitFor: async (condition, timeout = 5000, interval = 100) => {
    const startTime = Date.now();
    while (Date.now() - startTime < timeout) {
      if (await condition()) {
        return true;
      }
      await new Promise(resolve => setTimeout(resolve, interval));
    }
    return false;
  },

  // Get current indexer status
  getStatus: async () => {
    const response = await global.api.get('/status');
    return response.data;
  },

  // Wait for indexer to process blocks
  waitForBlocks: async (minBlocks = 1, timeout = 10000) => {
    const initialStatus = await global.testUtils.getStatus();
    const initialBlock = Math.max(initialStatus.Transfer || 0, initialStatus.Approval || 0);

    return await global.testUtils.waitFor(async () => {
      const status = await global.testUtils.getStatus();
      const currentBlock = Math.max(status.Transfer || 0, status.Approval || 0);
      return currentBlock >= initialBlock + minBlocks;
    }, timeout);
  }
};

// Global test hooks
beforeAll(async () => {
  // Verify API is accessible
  try {
    const response = await global.api.get('/health');
    if (response.status !== 200) {
      throw new Error('API health check failed');
    }
  } catch (error) {
    console.error('Failed to connect to API:', error.message);
    throw error;
  }
});
