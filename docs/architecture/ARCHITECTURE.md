# Architecture & Design Document
## PredictionMarket Protocol — On-Chain Prediction Market (Option D)

---

## 1. System Context (C4 Level 1)

```
┌──────────────────────────────────────────────────────────────────┐
│                        External Actors                           │
│                                                                  │
│  [Trader]  [LP Provider]  [DAO Voter]  [Resolver]  [Developer]  │
└──────────────────┬───────────────────────────────────────────────┘
                   │  HTTP/JSON-RPC
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                     PredictionMarket dApp                        │
│              (React/HTML frontend on IPFS/Vercel)                │
│         Reads from: The Graph subgraph + RPC                     │
│         Writes to:  Base Sepolia via MetaMask                    │
└──────────────────┬────────────────────────────┬──────────────────┘
                   │                            │
                   ▼                            ▼
      ┌────────────────────────┐   ┌────────────────────────┐
      │   Base Sepolia (L2)    │   │    The Graph           │
      │   Smart Contracts      │   │    Subgraph            │
      └────────────────────────┘   └────────────────────────┘
                   │
                   ▼
      ┌────────────────────────┐
      │   Chainlink Oracle     │
      │   (ETH/USD price feed) │
      └────────────────────────┘
```

---

## 2. Container / Component Diagram

```
                        ┌─────────────────────────────────────────────────┐
                        │              Smart Contract Layer                │
                        │                                                  │
 User ──► Proxy ──────► │  PredictionMarketV1 (UUPS)                      │
           ERC1967      │  ├── CPMM AMM (x*y=k, 0.3% fee)                │
                        │  ├── ERC-1155 Outcome Shares (YES=1, NO=2)      │
                        │  ├── State Machine (Open→Closed→Resolved→...)   │
                        │  ├── ReentrancyGuard                            │
                        │  └── AccessControl (RESOLVER, PAUSER, UPGRADER) │
                        │                    │                             │
                        │                    ▼                             │
                        │  FeeVault (ERC-4626)  ◄── 0.3% fees            │
                        │                    │                             │
                        │  MarketFactory     │                             │
                        │  ├── CREATE (non-deterministic)                  │
                        │  └── CREATE2 (deterministic)                     │
                        │                    │                             │
                        │  GovernanceToken (ERC20Votes + ERC20Permit)     │
                        │  MarketGovernor (OZ Governor)                   │
                        │  MarketTimelock (2-day delay)                   │
                        │  Treasury (AccessControl, Timelock-controlled)  │
                        │                    │                             │
                        │  ChainlinkAdapter  │                             │
                        │  └── Staleness check (1h threshold)             │
                        └─────────────────────────────────────────────────┘

 Access Control Roles:
   DEFAULT_ADMIN_ROLE  → MarketTimelock (after setup; renounced from deployer)
   RESOLVER_ROLE       → Trusted resolver EOA / multisig
   PAUSER_ROLE         → Trusted ops key
   UPGRADER_ROLE       → MarketTimelock (upgrades require DAO vote)
   DEPOSITOR_ROLE      → MarketFactory (on FeeVault)
   EXECUTOR_ROLE       → MarketTimelock (on Treasury)
   CREATOR_ROLE        → Deployer / DAO (on MarketFactory)

 External Dependencies:
   Chainlink  → price feed for oracle resolution check
   The Graph  → event indexing for frontend
   Base Sepolia → L2 deployment (Optimistic Rollup)
```

---

## 3. Sequence Diagrams

### 3.1 Buy Shares (Trader)

```
Trader          USDC          PredictionMarketV1     FeeVault
  │                │                    │                │
  │──approve()────►│                    │                │
  │◄──────────────-│                    │                │
  │                │                    │                │
  │──buyShares(YES, 100 USDC, minOut)──►│                │
  │                │                    │                │
  │                │   transferFrom()   │                │
  │                │◄───────────────────│                │
  │                │                    │                │
  │                │                    │─depositFee()──►│
  │                │                    │  (0.3 USDC)    │
  │                │                    │◄───────────────│
  │                │                    │                │
  │◄──_mint(YES shares)─────────────────│                │
  │                │                    │                │
  │◄──SharesBought event────────────────│                │
```

### 3.2 Governance: Propose → Vote → Queue → Execute

```
Alice          Governor        Timelock        Treasury
  │                │               │               │
  │─propose()─────►│               │               │
  │◄─proposalId────│               │               │
  │                │               │               │
  │  [wait 1 day voting delay]     │               │
  │                │               │               │
  │─castVote(For)─►│               │               │
  │                │               │               │
  │  [wait 1 week voting period]   │               │
  │                │               │               │
  │─queue()───────►│               │               │
  │                │─scheduleBatch►│               │
  │                │               │               │
  │  [wait 2 day timelock delay]   │               │
  │                │               │               │
  │─execute()─────►│               │               │
  │                │─executeBatch─►│               │
  │                │               │─withdrawETH──►│
  │                │               │               │─transfer()─► recipient
```

### 3.3 Market Resolution + Claim

```
Resolver       PredictionMarketV1     ChainlinkAdapter    Winner
  │                    │                      │               │
  │─closeMarket()─────►│                      │               │
  │                    │                      │               │
  │─resolveMarket(YES)►│                      │               │
  │                    │─isFresh()────────────►               │
  │                    │◄─true─────────────────               │
  │                    │                      │               │
  │                    │ state = Resolved      │               │
  │                    │                      │               │
  │  [wait 1 day dispute window]              │               │
  │                    │                      │               │
  │─settleMarket()────►│                      │               │
  │                    │ state = Settled       │               │
  │                    │                      │               │
  │                    │                      │─claimWinnings►│
  │                    │                      │               │
  │                    │◄──────────────────────────────────────│
  │                    │─_burn(YES shares)────────────────────►│
  │                    │─safeTransfer(payout)─────────────────►│
```

---

## 4. Storage Layout

### PredictionMarketV1 (UUPS upgradeable)

Critical invariant: storage slots must never change across upgrades.
New variables in V2+ must consume slots from `__gap`.

| Slot range | Variable | Type |
|---|---|---|
| 0–49 | OZ Initializable gap | uint256[50] |
| 50–99 | OZ UUPSUpgradeable gap | uint256[50] |
| 100–149 | OZ AccessControl gap | uint256[50] |
| 150–199 | OZ ReentrancyGuard gap | uint256[50] |
| 200–249 | OZ Pausable gap | uint256[50] |
| 250–299 | OZ ERC1155 gap | uint256[50] |
| 300 | state | MarketState (uint8) |
| 301 | question | string |
| 302 | resolutionTime | uint256 |
| 303 | disputeWindow | uint256 |
| 304 | oracle | address |
| 305 | collateral | address |
| 306 | feeVault | address |
| 307 | reserveYES | uint256 |
| 308 | reserveNO | uint256 |
| 309 | winningOutcome | Outcome (uint8) |
| 310 | resolvedAt | uint256 |
| 311 | totalCollateral | uint256 |
| 312 | totalLPShares | uint256 |
| 313 | lpShares | mapping(address => uint256) |
| 314 | hasClaimed | mapping(address => bool) |
| 315–356 | __gap | uint256[42] |

### V2 upgrade: slots 315–316 consumed by `referencePrice` (uint256) and `referenceDecimals` (uint8). `__gap` shrinks to `uint256[40]`.

---

## 5. Trust Assumptions

| Actor | Powers | Risk if compromised |
|---|---|---|
| DEFAULT_ADMIN_ROLE (Timelock) | Grant/revoke all roles | Full protocol control — mitigated by 2-day delay + DAO vote |
| RESOLVER_ROLE | Resolve markets, resolve disputes | Wrong outcome → winners lose funds. Mitigated by dispute window |
| PAUSER_ROLE | Pause all trading | DoS on trading. Mitigated by unpausing via same role |
| UPGRADER_ROLE (Timelock) | Upgrade implementation | Full code change. Requires DAO vote + 2-day delay |
| DEPOSITOR_ROLE | Push fees into FeeVault | Can inflate vault accounting. Granted only to MarketFactory |
| CREATOR_ROLE | Deploy new markets | Can deploy malicious market. Granted only to trusted deployer/DAO |

**If multisig is compromised:** RESOLVER_ROLE and PAUSER_ROLE could be abused immediately.
UPGRADER_ROLE and treasury withdrawals are protected by Timelock — community has 2 days to react.

---

## 6. Design Decisions Log (ADRs)

### ADR-001: CPMM over LMSR
**Context:** Spec allows LMSR or CPMM for AMM pricing.
**Options:** LMSR (logarithmic market scoring rule) vs CPMM (constant product).
**Decision:** CPMM (x*y=k). Simpler implementation, well-understood invariant, compatible with standard LP token design, easier to audit and fuzz test.
**Consequences:** Price impact is higher for large trades vs LMSR. Accepted tradeoff for auditability.

### ADR-002: ERC-1155 for outcome shares
**Context:** Need to represent YES and NO shares per market.
**Options:** Two separate ERC-20 per market vs ERC-1155.
**Decision:** ERC-1155 with YES_ID=1, NO_ID=2. Single contract, built-in batch operations, lower deploy cost per market.
**Consequences:** Frontend must use `balanceOf(address, id)` — slightly less intuitive than ERC-20 but tooling is well-supported.

### ADR-003: Per-market UUPS proxy vs factory-owned upgrades
**Context:** Each market is deployed as a UUPS proxy.
**Decision:** Each proxy points to same implementation. Upgrades via DAO vote upgrade the implementation; all markets upgrade atomically.
**Consequences:** Cannot upgrade individual markets selectively. Acceptable — the spec requires a demonstrated V1→V2 path, not per-market versioning.

### ADR-004: Dispute window before settlement
**Context:** Oracle could be manipulated or wrong.
**Decision:** 1-day dispute window after resolution. Any address can open a dispute. RESOLVER_ROLE then re-resolves.
**Consequences:** Settlement delayed by 1 day minimum. Accepted for security.

### ADR-005: L2 choice — Base Sepolia
**Context:** Spec allows Arbitrum Sepolia, Optimism Sepolia, Base Sepolia, zkSync Sepolia.
**Decision:** Base Sepolia. Best Chainlink feed availability, Coinbase ecosystem, lower fees, good block explorer (Basescan).
**Consequences:** Optimistic rollup — 7-day withdrawal delay to L1 (irrelevant for testnet demo).
