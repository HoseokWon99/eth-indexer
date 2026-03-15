# Test Contracts

This directory contains Solidity contracts for testing the eth-indexer with Anvil (local Ethereum node).

## Structure

```
contracts/
├── src/              # Contract source code
│   └── TestToken.sol # Simple ERC20-like token
├── script/           # Foundry deployment scripts
│   ├── Deploy.s.sol          # Deploy test tokens
│   └── GenerateEvents.s.sol  # Generate test events
├── test/             # Contract unit tests
└── foundry.toml      # Foundry configuration
```

## TestToken Contract

Simple ERC20-like token that emits standard Transfer and Approval events:

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
event Approval(address indexed owner, address indexed spender, uint256 value);
```

## Usage

### Build Contracts

```bash
make contracts-build
# or
cd test/contracts && forge build
```

### Run Contract Tests

```bash
make contracts-test
# or
cd test/contracts && forge test
```

### Deploy to Anvil (Manual)

```bash
# Start Anvil
anvil --mnemonic "test test test test test test test test test test test junk"

# In another terminal
cd test/contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --legacy
```

## Test Data

When deployed via `scripts/anvil/deploy-contracts.sh`:

- **Token1 (TUSDC)**: 50 Transfer events + 30 Approval events
- **Token2 (TUSDT)**: 40 Transfer events + 20 Approval events
- **Total**: 140 events (plus 2 constructor Transfer events)

All events use deterministic addresses:
- Alice: `0x1111111111111111111111111111111111111111`
- Bob: `0x2222222222222222222222222222222222222222`
- Charlie: `0x3333333333333333333333333333333333333333`
