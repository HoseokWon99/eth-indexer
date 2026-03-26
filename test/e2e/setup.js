const fs = require('fs/promises');

const PG_OPTIONS = {
    host: process.env.POSTGRES_HOST || 'localhost',
    port: parseInt(process.env.POSTGRES_PORT || '5432'),
    database: process.env.POSTGRES_DB || 'eth_indexer',
    user: process.env.POSTGRES_USER || 'test',
    password: process.env.POSTGRES_PASSWORD || '0000',
}

const TX_PATH = process.env.TX_PATH || `${ __dirname }/../contracts/broadcast/GenerateEvents.s.sol/31337/run-latest.json`;

function getTopic(tx) {
    const topic = tx.function.split('(')[0].trim();
    return topic.replace(topic[0], topic[0].toUpperCase());
}

async function loadTransactions(txPath) {
    const raw = await fs.readFile(txPath, 'utf8');
    const data = JSON.parse(raw);
    return new Map(data.transactions.map(tx => [tx.hash, tx]));
}

const INDEXER_URL = process.env.INDEXER_URL || 'http://localhost:8081';
const API_URL = process.env.API_URL || 'http://localhost:8082';

module.exports = { PG_OPTIONS, TX_PATH, INDEXER_URL, API_URL,  getTopic, loadTransactions };