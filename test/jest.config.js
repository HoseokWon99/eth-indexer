module.exports = {
  testEnvironment: 'node',
  testTimeout: 30000,
  verbose: true,
  collectCoverageFrom: [
    '**/*.test.js'
  ],
  coverageDirectory: 'coverage',
  testMatch: [
    '**/*.test.js'
  ],
  setupFilesAfterEnv: ['<rootDir>/setup.js']
};
