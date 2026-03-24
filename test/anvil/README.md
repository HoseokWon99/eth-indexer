# Anvil Test Container

A containerized [Anvil](https://book.getfoundry.sh/anvil/) node used as a local Ethereum RPC endpoint during integration tests. It provides a deterministic, ephemeral chain that optionally forks mainnet state.

## Purpose

The indexer integration tests require a live Ethereum RPC endpoint to exercise the full indexing pipeline: log subscription, contract event filtering, ABI decoding, and Postgres persistence. This container replaces a real node with a fast, scriptable local chain that resets on each test run.

The `contract-deployer` service in `docker-compose.test.yml` depends on this container being healthy before deploying test contracts and generating events.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ANVIL_HOST` | `0.0.0.0` | Interface Anvil listens on. Must be `0.0.0.0` inside Docker to be reachable from other containers. |
| `ANVIL_PORT` | `8545` | Port Anvil listens on. |
| `ANVIL_BLOCK_TIME` | `1` | Interval in seconds between automatically mined blocks. |
| `ANVIL_MNEMONIC` | `test test test ... junk` | BIP-39 mnemonic used to derive pre-funded accounts. The well-known test mnemonic produces a deterministic set of accounts. |
| `FORK_URL` | `https://eth.llamarpc.com` | Remote RPC endpoint to fork from. See [Fork Mode](#fork-mode) below. |

## Fork Mode

The entrypoint uses a shell conditional expansion to control fork behavior:

```sh
${FORK_URL:+--fork-url $FORK_URL}
```

This passes `--fork-url` to Anvil **only when `FORK_URL` is set to a non-empty string**. When `FORK_URL` is unset or empty, Anvil starts a blank chain from genesis with no forked state.

The default value in the Dockerfile is `https://eth.llamarpc.com` (Ethereum mainnet via LlamaRPC). Override this in `docker-compose.test.yml` or at the command line to point at a different network or a local archive node.

To disable forking entirely, pass an empty string:

```bash
docker run --rm -e FORK_URL="" test/anvil
```

## Test Accounts

The default mnemonic (`test test test test test test test test test test test junk`) derives 10 pre-funded accounts, each holding 10,000 ETH on the local chain.

**Account 0**

| Field | Value |
|---|---|
| Address | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| Private key | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |

Account 0's private key is used by `scripts/anvil/deploy-contracts.sh` to broadcast contract deployments and generate test events.

These credentials are publicly known and must never be used on any real network.

## Connection

Anvil serves both HTTP and WebSocket on the same port. No additional flags are required.

| Context | HTTP | WebSocket |
|---|---|---|
| Host machine | `http://localhost:8545` | `ws://localhost:8545` |
| Other containers on the same Docker network | `http://anvil:8545` | `ws://anvil:8545` |

The `contract-deployer` service uses `http://anvil:8545` for one-off RPC calls. The indexer service connects via WebSocket (`ws://anvil:8545`) to subscribe to new block headers.

## Running

### Standalone (Docker)

```bash
# Build
docker build -f test/anvil/Dockerfile -t eth-indexer-anvil .

# Run with fork (default)
docker run --rm -p 8545:8545 eth-indexer-anvil

# Run with a custom fork URL
docker run --rm -p 8545:8545 -e FORK_URL=https://rpc.ankr.com/eth eth-indexer-anvil

# Run without forking (blank chain)
docker run --rm -p 8545:8545 -e FORK_URL="" eth-indexer-anvil
```

### Via Docker Compose (integration tests)

```bash
# Set FORK_URL or leave unset to use the default
export FORK_URL=https://eth.llamarpc.com

docker compose -f docker-compose.test.yml up anvil
```

The full test stack starts Anvil, Postgres, Valkey, the contract deployer, the indexer, and the API server in dependency order:

```bash
docker compose -f docker-compose.test.yml up --build
```

### Via Make

```bash
# Run Anvil directly on the host (no Docker)
make anvil-fork

# Override the fork URL
make anvil-fork FORK_URL=https://rpc.ankr.com/eth
```

## Health Check

The container reports healthy once `cast client` returns a successful response from the local RPC endpoint:

```bash
cast client --rpc-url http://localhost:8545
```

Interval: 2 s, timeout: 5 s, retries: 10. Other services that depend on Anvil use `condition: service_healthy` in `docker-compose.test.yml` to wait until the node is ready before proceeding.

## Notes

- The chain ID when forking Ethereum mainnet is `1`. When running without a fork the default chain ID is `31337`.
- The deployment broadcast directory is keyed on chain ID (`broadcast/Deploy.s.sol/31337`), so the contract deployer script expects the non-fork chain ID `31337` unless the fork source also uses that ID.
- No state is persisted between runs. Each `docker compose up` starts a fresh chain.
