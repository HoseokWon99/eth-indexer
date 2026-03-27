const { readFile } = require('fs/promises');
const { createWriteStream } = require('fs');
const { Client } = require("pg");

const PG_OPTIONS = {
    host: process.env.POSTGRES_HOST || 'localhost',
    port: parseInt(process.env.POSTGRES_PORT || '5434'),
    database: process.env.POSTGRES_DB || 'eth_indexer',
    user: process.env.POSTGRES_USER || 'test',
    password: process.env.POSTGRES_PASSWORD || '0000',
}

const TX_PATH = process.env.TX_PATH || `${ __dirname }/../contracts/broadcast/GenerateEvents.s.sol/31337/run-latest.json`;

function getTopic(tx) {
    const topic = tx.function.split('(')[0].trim();
    return topic.replace(topic[0], topic[0].toUpperCase());
}

const columnNames = [
    "topic",
    "contract_address",
    "tx_hash",
    "block_hash",
    "block_number",
    "log_index",
    "data",
    "timestamp",
];

async function selectEventRecords(client) {
    const { rows } = await client.query(`SELECT * FROM event_records`);
    const ws = createWriteStream(`${ __dirname }/data/${Date.now()}_event_records.csv`);

    columnNames.forEach((cn, idx) => {
       ws.write(cn);
       idx < columnNames.length - 1 ? ws.write(',') : ws.write('\n');
    });

    for (const row of rows) {
        columnNames.forEach((cn, idx) => {
            ws.write(row[cn]);
            idx < columnNames.length - 1 ? ws.write(',') : ws.write('\n');
        });
    }

    ws.end();
    return rows;
}

async function loadTransactions(txPath) {
    const raw = await readFile(txPath, 'utf8');
    const data = JSON.parse(raw);
    return new Map(data.transactions.map(tx => [tx.hash, tx]));
}

const INDEXER_URL = process.env.INDEXER_URL || 'http://localhost:8081';
const API_URL = process.env.API_URL || 'http://localhost:8082';
const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://localhost:8090';

module.exports = {
    PG_OPTIONS, TX_PATH, INDEXER_URL, API_URL, DASHBOARD_URL,
    getTopic, selectEventRecords, loadTransactions,
};