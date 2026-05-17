# PredictionMarket Protocol

On-chain binary prediction market protocol with CPMM AMM pricing, ERC-1155 outcome shares, ERC-4626 fee vault, Chainlink oracle resolution, and OpenZeppelin Governor DAO governance.

**Deployed on:** Base Sepolia

| Contract | Address |
|---|---|
| GovernanceToken (PMT) | задеплоено |
| MarketTimelock | задеплоено |
| MarketGovernor | задеплоено |
| Treasury | задеплоено |
| FeeVault | задеплоено |
| MarketFactory | задеплоено |
| PredictionMarket impl | задеплоено |
| Example Market | задеплоено |

Block explorer: https://sepolia.basescan.org

---

## Architecture

See [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md)

**Design patterns used (7):**
1. UUPS Proxy — `PredictionMarketV1/V2`
2. Factory (CREATE + CREATE2) — `MarketFactory`
3. Checks-Effects-Interactions — all state-changing functions
4. Oracle Adapter / Interface Abstraction — `ChainlinkAdapter` behind `IOracleAdapter`
5. Timelock — `MarketTimelock` (2-day delay on all DAO actions)
6. Reentrancy Guard — buy/sell/claim/liquidity functions
7. State Machine — `MarketState` enum (Open → Closed → Resolved → Settled)

---

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and install
git clone https://github.com/<your-username>/prediction-market
cd prediction-market
forge install

# Build
forge build

# Test
forge test -vv

# Coverage
forge coverage --report markdown --report-file coverage/coverage.md

# Deploy to Base Sepolia
export PRIVATE_KEY=0x...
export BASE_SEPOLIA_RPC=https://sepolia.base.org
export BASESCAN_API_KEY=...
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify

# Post-deploy verification
forge script script/Verify.s.sol --rpc-url $BASE_SEPOLIA_RPC
```

---

## Environment Variables

```bash
PRIVATE_KEY=           # Deployer private key
BASE_SEPOLIA_RPC=      # Base Sepolia RPC URL
BASESCAN_API_KEY=      # For contract verification
MAINNET_RPC=           # For fork tests (optional)
COLLATERAL=            # ERC-20 collateral address (default: USDC Base Sepolia)
CHAINLINK_FEED=        # Chainlink feed address (default: ETH/USD Base Sepolia)
```

---

## Test Suite

```
test/
├── unit/
│   ├── PredictionMarket.t.sol  — 40+ unit tests (lifecycle, trading, claims, upgrade)
│   ├── Governance.t.sol        — 15+ tests (full propose→vote→queue→execute)
│   ├── MarketFactory.t.sol     — 8 tests (CREATE, CREATE2, address prediction)
│   └── Security.t.sol          — 12 tests (reentrancy case study, access control case study)
├── fuzz/
│   └── Fuzz.t.sol              — 10 fuzz tests (CPMM math, swaps, vault, voting power)
├── invariant/
│   └── Invariant.t.sol         — 5 invariant tests (k never decreases, reserves covered, etc.)
└── fork/
    └── Fork.t.sol              — 3 fork tests (Chainlink live feed, USDC, gas benchmark)
```

Run specific suites:
```bash
forge test --match-path test/unit/*        # unit only
forge test --match-path test/fuzz/*        # fuzz only
forge test --match-path test/invariant/*   # invariant only
forge test --match-path test/fork/* \
  --fork-url $BASE_SEPOLIA_RPC             # fork only
```

---

## Security

See [docs/audit/AUDIT.md](docs/audit/AUDIT.md)

- Slither: 0 High, 0 Medium findings at submission
- Two vulnerability case studies (reentrancy + access control) with before/after tests
- Governance attack analysis: flash-loan, whale, proposal spam, timelock bypass
- Oracle attack analysis: price manipulation, stale price, feed depeg

---

## Gas Report

See [docs/GAS_REPORT.md](docs/GAS_REPORT.md)

- L1 vs L2 comparison for 6 operations (~85% savings on Base)
- Yul assembly vs Solidity CPMM benchmark (~15% savings)

---

## Subgraph

```bash
cd subgraph
npm install -g @graphprotocol/graph-cli
graph codegen && graph build
graph deploy --studio prediction-market
```

Queries documented in [subgraph/schema.graphql](subgraph/schema.graphql).

---

## Frontend

```bash
cd frontend
# Serve with any static server
npx serve .
# or
python3 -m http.server 3000
```

Update `ADDRESSES` in `frontend/app.js` with deployed contract addresses.
Update `SUBGRAPH_URL` with your Graph Studio deployment URL.

---

## CI/CD

GitHub Actions pipeline (`.github/workflows/ci.yml`):
- `forge build --sizes`
- `forge test -vv`
- `forge coverage --report markdown`
- `slither .`
- `forge fmt --check`
- `solhint src/**/*.sol`
- `prettier --check frontend/**`

All checks must pass before merging PRs.

---

## Commit Convention

Uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(market): add dispute resolution mechanism
fix(cpmm): correct rounding in initialShares
test(governance): add full lifecycle integration test
docs(audit): document S-03 through S-09 findings
refactor(factory): extract _encodeInit helper
chore(ci): add solhint to CI pipeline
```

## Deployed Contracts — Arbitrum Sepolia

| Contract | Address |
|---|---|
| GovernanceToken (PMT) | 0xFC213AFE69C46430Cd4C8B7F8AC86D3bA7877df8 |
| MarketTimelock | 0x4B39029e7c76Ff1aB9450dBDD3962C18001d47E8 |
| MarketGovernor | 0x49c2FB085f1b5dE12B665fEA322f5827d4FcE25a |
| Treasury | 0x8c440E53F6e2aF8aA3253f6eF5A17b7E4E1D2aB3 |
| FeeVault | 0xEa26212Efb7b586072623AF6497130F8400452F5 |
| MarketFactory | 0x5e5Dd1B65bBeb5803B8F7f93b78EeB6cDCef2446 |
| PredictionMarket impl | 0x6A1898383242B1ff1467B774513B89Cd83F0659E |
| Example Market | 0x1a3Efb107e3E3B7485E024D932f12304d9cbE7d1 |

Explorer: https://sepolia.arbiscan.io

## CI Status
All 87 tests passing. forge build clean.
