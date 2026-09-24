# EnDAOsment Governance Architecture

## 1. System Philosophy & Design Principles

Traditional DAO governance often forces every initiative to be proposed, debated, and voted on individually through a single binary (yes/no) token-weighted vote. This model suffers from three major failure modes:
1. **Voter Fatigue & Bounded Rationality**: Community members cannot rationally review dozens of independent proposals per week without information overload.
2. **Plutocratic Dominance**: Simple ERC-20 token weighting allows wealthy token holders ("whales") to pass proposals regardless of community consensus or contributor sentiment.
3. **De-coupling of Value vs. Resource Allocation**: A proposal may be ideologically valuable ("WHY") but excessively costly or poorly budgeted ("HOW MUCH"). Voting "yes" combines both judgments into a blunt decision.

The **EnDAOsment Multi-Stage Governance Framework** solves this by decomposing collective decision-making into three distinct, sequential stages:

```
[Proposal Submitted]
         │
         ▼
 ┌──────────────────────────────────────────┐
 │  STAGE 1: APPROVAL GOVERNOR (Value)      │
 │  • Question: "WHY should we do this?"    │
 │  • Voting: Ternary (For / Against / Abs) │
 │  • Weight: Contribution Reputation Score │
 │  • Threshold: Quorum Score & Majority    │
 └────────────────────┬─────────────────────┘
                      │ Passed
                      ▼
 ┌──────────────────────────────────────────┐
 │  STAGE 2: QUADRATIC GOVERNOR (Resource)  │
 │  • Question: "HOW MUCH should we fund?"  │
 │  • Voting: Quadratic Credit Allocation   │
 │  • Voting Power: V = ⌊sqrt(C)⌋           │
 │  • Weight: Preference Intensity          │
 └────────────────────┬─────────────────────┘
                      │ Succeeded
                      ▼
 ┌──────────────────────────────────────────┐
 │  STAGE 3: TIMELOCK / ACTION COMMITTEE    │
 │  • Enforcement & Cooldown Delay          │
 │  • On-chain execution of batched calls   │
 └──────────────────────────────────────────┘
```

---

## 2. Core Contracts Overview

### A. `GovernorGeneral.sol` (CORE Orchestrator)
`GovernorGeneral` is the central hub of the governance ecosystem. It acts as the single public entry point for creating, tracking, and executing proposals.
- **State Machine**: Tracks proposal states through `ProposalStage`:
  - `Pending`: In cooldown delay (`votingDelay`) after submission.
  - `Approval`: Active in Stage 1 Approval voting for `approvalPeriod` blocks.
  - `Quadratic`: Active in Stage 2 Quadratic voting for `quadraticPeriod` blocks.
  - `Succeeded`: Quadratic quorum met and positive votes achieved.
  - `Queued`: Queued into the `TimelockController` awaiting delay maturity.
  - `Executed`: Calls executed on-chain by the Timelock.
  - `Defeated`: Failed either Stage 1 approval quorum or Stage 2 quadratic quorum.
  - `Canceled`: Canceled by the proposer or emergency admin.
- **Delegated Dispatch**: When `castVote(proposalId, support)` is called on `GovernorGeneral`, it inspects the current stage and forwards the vote to the appropriate Governor (`ApprovalGovernor` or `QuadraticGovernor`).

### B. `MemberToken.sol` (ERC-1155 Soulbound Token)
Membership in the DAO is tracked via non-transferable ERC-1155 soulbound tokens.
- **Soulbound Property**: Peer-to-peer transfers are blocked in `_update`:
  ```solidity
  if (from != address(0) && to != address(0)) {
      revert SoulboundTokenTransferDisabled();
  }
  ```
  This eliminates flash-loan attacks, temporary token borrows, and vote-buying markets.
- **Historical Balance Checkpointing**: Integrates OpenZeppelin's `Checkpoints.Trace208`. When proposals are submitted at block $N$, voting eligibility is strictly determined at the snapshot block via:
  ```solidity
  memberToken.getPastBalanceOf(voter, tokenId, snapshot);
  ```

### C. `ApprovalGovernor.sol` (Stage 1: Proposal Value Ranking)
Stage 1 filters proposals based on intrinsic value and organizational alignment.
- **Vote Options**: `0 = Against`, `1 = For`, `2 = Abstain`.
- **Reputation Weighting**: The weight of each vote is derived from the voter's **Contribution Reputation Score (CRS)** queried from `ICrsManager.getCrs(voter, tokenId)`. If score is 0, a baseline weight of $1\times 10^{18}$ is applied.
- **Pass Condition**:
  $$\text{hasPassed} \iff (\text{forVotes} \ge \text{quorumScore}) \land (\text{forVotes} > \text{againstVotes})$$

### D. `QuadraticGovernor.sol` (Stage 2: Resource Allocation)
Proposals that clear Stage 1 advance to Stage 2 to measure community preference intensity and allocate budget/resources.
- **Credit Budget**: Derived dynamically from the voter's reputation:
  $$\text{CreditBudget} = \max\left(\text{MIN\_CREDITS}, \frac{\text{CRS}}{\text{CREDITS\_SCALE}}\right)$$
- **Quadratic Math**: To express a voting weight of $V$, a voter must expend $C = V^2$ credits. The contract calculates votes awarded from credits spent as:
  $$V = \lfloor\sqrt{C}\rfloor$$
- **Native Credit Accounting**: Credits are tracked inside contract storage (`spentCredits[proposalId][voter]`). No volatile ERC-20 token is minted or transferred, preventing supply inflation bugs.
- **Pass Condition**:
  $$\text{hasPassed} \iff (\text{forVotes} \ge \text{quadraticQuorum}) \land (\text{forVotes} > \text{againstVotes})$$

### E. `TimelockControllerUpgradeable.sol` (Stage 3: Timelock Enforcement)
- Standard OpenZeppelin timelock that enforces a mandatory cooldown delay (e.g., 2 days) between proposal passage and execution.
- Only `GovernorGeneral` holds the `PROPOSER_ROLE` and `CANCELLER_ROLE`.
- `EXECUTOR_ROLE` is set to `address(0)` (open execution once the timelock expires).

### F. `ContractsFactory.sol` (Federated DAO Factory)
Enables independent organizations and agencies to deploy their own isolated, customized multi-stage DAO ecosystems via lightweight ERC-1967 proxies:
- Holds pre-deployed canonical implementation contracts.
- Clones and initializes independent proxies for each agency.
- Transfers administrative ownership of all contracts directly to the agency's administrator.

---

## 3. Quadratic Voting Mathematical Model

In standard 1-token-1-vote systems, an actor with 1,000 tokens has 1,000 times the influence of an actor with 1 token. In quadratic voting:
- Cost of $V$ votes is $V^2$ credits.
- A voter with 100 credits can cast $\sqrt{100} = 10$ votes.
- A voter with 10,000 credits can cast $\sqrt{10000} = 100$ votes.

This sub-linear scaling gives small groups of passionate contributors an effective voice against indifferent majorities, while discouraging single-interest concentration.

### Precision & Properties Proved by Fuzzing
Our test suite includes Foundry property-based fuzz tests ([`test/QuadraticMath.t.sol`](../test/QuadraticMath.t.sol)):
1. **Square Root Property**: $\forall C \in [0, 2^{128}-1]$:
   $$V^2 \le C < (V + 1)^2 \quad \text{where } V = \lfloor\sqrt{C}\rfloor$$
2. **Strict Monotonicity**:
   $$C_1 < C_2 \implies \lfloor\sqrt{C_1}\rfloor \le \lfloor\sqrt{C_2}\rfloor$$
3. **Credit Budget Scaling**: Verified across CRS scores from 0 up to 10 billion ($10^{28}$).

---

## 4. Upgradeability & Proxy Model

All contracts use OpenZeppelin's **UUPS (Universal Upgradeable Proxy Standard)**:
- Implementations include `_disableInitializers()` in the constructor to protect uninitialized logic contracts.
- Upgrade authorization is strictly enforced:
  - `MemberToken`: `onlyRole(UPGRADER_ROLE)`
  - `ApprovalGovernor`: `onlyOwner`
  - `QuadraticGovernor`: `onlyOwner`
  - `GovernorGeneral`: `onlyOwner`
  - `ContractsFactory`: `onlyOwner`
- Every contract reserves a 50-slot storage gap (`uint256[N] private __gap;`) to allow seamless addition of future state variables without storage collision.

---

## 5. Advanced Governance Features

### 5.1 EIP-712 Gasless Voting (Meta-Transactions)
To eliminate gas friction for DAO members, `GovernorGeneral` integrates native EIP-712 typed signature verification via OpenZeppelin's `SignatureChecker` (supporting both EOA signatures and ERC-1271 smart contract wallets like Safe):
- **Approval Stage Signature**:
  ```solidity
  ApprovalVote(uint256 proposalId, uint8 support, uint256 tokenId, address voter, uint256 nonce)
  ```
  Submitted via `castApprovalVoteBySig(...)` with either 65-byte `signature` or `(uint8 v, bytes32 r, bytes32 s)`.
- **Quadratic Stage Signature**:
  ```solidity
  QuadraticVote(uint256 proposalId, uint8 support, uint256 creditsToSpend, uint256 tokenId, address voter, uint256 nonce)
  ```
  Submitted via `castQuadraticVoteBySig(...)` with either `signature` or `(v, r, s)`.
- **Replay Protection**: Per-voter sequential `nonces[voter]` incrementing after each signed vote prevents cross-submission replay attacks.

### 5.2 Epoch-Based Batched Bounded Rationality Budgeting
To prevent voter exhaustion and reflect real-world fiscal constraints, proposals are grouped into **Governance Epochs** (`currentEpoch`):
- Rather than granting a fresh credit budget for every single proposal, each voter receives an aggregate credit pool per epoch:
  $$\sum_{p \in \text{Epoch}} C_{p, \text{voter}} \le \text{CreditBudget}_{\text{voter}}$$
- `QuadraticGovernor` tracks cumulative expenditure via `epochSpentCredits[epochId][voter]`.
- As a voter allocates credits across multiple proposals in the same epoch, their remaining spending capacity decreases, forcing deliberate prioritization of scarce political capital.
- Epochs are advanced permissionlessly upon duration expiry via `advanceEpoch()`.

### 5.3 Snapshot Reputation Scoring (Flash-Loan / Boost Immunity)
To guarantee that reputation cannot be artificially manipulated mid-vote:
- `ApprovalGovernor` and `QuadraticGovernor` query historical reputation snapshots via `ICrsManager.getPastCrs(voter, tokenId, snapshot)`.
- Stage 1 snapshots at `p.voteStart`.
- Stage 2 snapshots at `p.quadraticStart`.
- Any external reputation score boosts awarded after a proposal begins do not inflate voting power for that active proposal.

### 5.4 Anti-Spam Proposal Deposit Bonds
To mitigate spam and low-effort governance bloat:
- `GovernorGeneral` supports configurable `proposalDeposit` bonds.
- Proposers must attach `msg.value >= proposalDeposit` when calling `propose()`.
- **Refund on Value Consensus**: If the proposal meets quorum and passes Stage 1, the full deposit is immediately refunded to the proposer upon advancing to Stage 2.
- **Slash to Treasury on Defeat**: If the proposal fails to achieve Stage 1 consensus, the deposit is slashed and forwarded directly to the DAO Timelock treasury.
- **Refund on Cancellation**: Proposers may cancel their proposal prior to execution and retrieve their deposit.

### 5.5 ERC-6372 Clock & Mode Unification
All governors unify their timekeeping with the underlying token standard:
- `GovernorGeneral`, `ApprovalGovernor`, and `QuadraticGovernor` implement ERC-6372 `clock()` and `CLOCK_MODE()`.
- Timekeeping automatically syncs with `memberToken.clock()`, ensuring seamless interoperability across both block-number and timestamp-based rollup networks (e.g. Arbitrum, Optimism, Base).

### 5.6 Standardized Stage Interface (`IStageGovernor`)
All modular stages implement the standardized `IStageGovernor` interface:
```solidity
interface IStageGovernor {
    function stageId() external view returns (uint8);
    function hasPassed(uint256 proposalId) external view returns (bool);
    function getVotes(uint256 proposalId) external view returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);
    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}
```
This enables independent agencies to swap in custom consensus modules (e.g., conviction voting, futarchy, ranked choice) without modifying `GovernorGeneral`.

---

## 6. Federated Beacon Proxy Architecture & Sovereign Overrides

To balance federal protocol-wide upgrades with local agency autonomy, the framework introduces the **Federated Beacon Proxy pattern** via [`FederatedBeaconProxy.sol`](../contracts/FederatedBeaconProxy.sol).

```
                      ┌──────────────────────────────────────────────┐
                      │            Federal Protocol Level            │
                      │     Canonical UpgradeableBeacon (Admin)      │
                      └──────────────────────┬───────────────────────┘
                                             │
                          ┌──────────────────┴──────────────────┐
                          │ tracks canonical implementation     │
                          ▼                                     ▼
          ┌───────────────────────────────┐     ┌───────────────────────────────┐
          │     Agency A (Federal Mode)   │     │   Agency B (Overridden Mode)  │
          │     FederatedBeaconProxy      │     │     FederatedBeaconProxy      │
          │  customImplementation = 0x0   │     │  customImplementation = 0x123 │
          │  ==> Resolves to Federal      │     │  ==> Resolves to Custom Logic │
          └───────────────────────────────┘     └───────────────┬───────────────┘
                                                                │
                                                                ▼
                                                ┌───────────────────────────────┐
                                                │   Agency B Custom Contract    │
                                                │  (Custom Quadratic Math / CRS)│
                                                └───────────────────────────────┘
```

### Sovereign Downstream Override
1. **Federal Default**: By default, each `FederatedBeaconProxy` delegates calls to `IBeacon(beacon).implementation()`. When the federal protocol team upgrades a beacon, all agencies in Federal Mode automatically receive the upgrade.
2. **Agency Override**: If an agency requires custom voting rules or objects to a federal upgrade, the agency administrator calls:
   ```solidity
   proxy.overrideImplementation(customLogicAddress);
   ```
   This writes `customLogicAddress` into the standard ERC-1967 implementation slot. The proxy immediately begins executing the custom contract, becoming **immune** to upstream federal beacon upgrades.
3. **Reversibility**: If the agency subsequently wishes to realign with the federal standard, the agency administrator calls:
   ```solidity
   proxy.resetToFederalBeacon();
   ```
   This clears the custom implementation slot, seamlessly resuming tracking of the federal beacon.
4. **Transparent Governance Access**: Sovereign admin methods (`overrideImplementation`, `resetToFederalBeacon`, `changeAgencyAdmin`) are selectively dispatched. Normal governance calls (e.g. `propose`, `castVote`, `transferOwnership`) pass transparently through `fallback()` to `_implementation()`, even when initiated by the agency administrator.

