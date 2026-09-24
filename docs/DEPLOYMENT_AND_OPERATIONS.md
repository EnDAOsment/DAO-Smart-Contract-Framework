# Deployment & Operations Manual

This guide covers deployment, configuration, and day-to-day governance operations for both the standalone protocol and federated agency instances.

---

## 1. Prerequisites & Tooling

The framework requires **Foundry** (`forge`, `cast`, `anvil`) with Solidity `0.8.27`:
```bash
# Verify foundry installation
forge --version
cast --version
anvil --version
```

Clone the repository and install dependencies:
```bash
git clone https://github.com/mrtingalingling/DAO-Smart-Contract-Framework.git
cd DAO-Smart-Contract-Framework
forge install
forge build
```

Run test suite to verify:
```bash
forge test
```

---

## 2. Local Sandbox Testing with Anvil

Start a local Anvil node in a dedicated terminal window:
```bash
anvil --port 8545
```

### A. Deploying the Contracts Factory Locally
```bash
forge script script/DeployFactory.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

### B. Deploying Standalone Direct DAO Locally
```bash
forge script script/DeployDirectDAO.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

---

## 3. Production / Testnet Deployment

Set required environment variables:
```bash
export RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
export PRIVATE_KEY="0x..." # Deployment private key
export ETHERSCAN_API_KEY="..." # For automated contract verification
```

Deploy canonical implementations and the `ContractsFactory` proxy:
```bash
forge script script/DeployFactory.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

---

## 4. End-to-End Proposal Lifecycle Walkthrough

Below are the exact commands to operate a governance proposal from submission to execution.

### Step 1: Submit a Proposal
A qualified member holding at least `proposalThreshold` badges creates a proposal:
```bash
# Parameters:
# targets, values, calldatas, description, memberTokenId
cast send $GOVERNOR_GENERAL \
  "propose(address[],uint256[],bytes[],string,uint256)(uint256)" \
  "[$TARGET_ADDRESS]" \
  "[0]" \
  "[$CALLDATA]" \
  "Proposal 1: Fund Community Grant" \
  1 \
  --rpc-url $RPC_URL \
  --private-key $MEMBER_KEY
```
Note the emitted `proposalId`.

### Step 2: Stage 1 Approval Voting (Value Ranking)
After the `votingDelay` has passed, the proposal enters `ProposalStage.Approval`.
Eligible badge holders cast their approval vote (`0 = Against`, `1 = For`, `2 = Abstain`):
```bash
cast send $GOVERNOR_GENERAL \
  "castVote(uint256,uint8)" \
  $PROPOSAL_ID \
  1 \
  --rpc-url $RPC_URL \
  --private-key $VOTER_KEY
```
*Note: Vote weight is automatically calculated based on the voter's Contribution Reputation Score (CRS).*

### Step 3: Advance to Stage 2 Quadratic Voting
Once `approvalPeriod` blocks have elapsed, any account can call `advanceToQuadratic`:
```bash
cast send $GOVERNOR_GENERAL \
  "advanceToQuadratic(uint256)" \
  $PROPOSAL_ID \
  --rpc-url $RPC_URL \
  --private-key $ANY_KEY
```
- If Stage 1 met `quorumScore` and positive majority, state changes to `ProposalStage.Quadratic`.
- If Stage 1 failed, state transitions to `ProposalStage.Defeated`.

### Step 4: Stage 2 Quadratic Voting (Resource Allocation)
Members cast their quadratic vote by specifying how many credits to spend:
```bash
# Parameters: proposalId, support (0=Against, 1=For, 2=Abstain), creditsToSpend
cast send $GOVERNOR_GENERAL \
  "castQuadraticVote(uint256,uint8,uint256)" \
  $PROPOSAL_ID \
  1 \
  10000 \
  --rpc-url $RPC_URL \
  --private-key $VOTER_KEY
```
*Note: Spending 10,000 credits generates $\sqrt{10000} = 100$ voting power.*

### Step 5: Finalize Stage 2
Once `quadraticPeriod` blocks have elapsed, finalize the proposal:
```bash
cast send $GOVERNOR_GENERAL \
  "finalizeQuadratic(uint256)" \
  $PROPOSAL_ID \
  --rpc-url $RPC_URL \
  --private-key $ANY_KEY
```
If quadratic votes meet `quadraticQuorum` and positive majority, the proposal transitions to `ProposalStage.Succeeded`.

### Step 6: Queue Proposal into Timelock
Queue the approved batch calls into the `TimelockController`:
```bash
cast send $GOVERNOR_GENERAL \
  "queue(uint256)" \
  $PROPOSAL_ID \
  --rpc-url $RPC_URL \
  --private-key $ANY_KEY
```
State changes to `ProposalStage.Queued`. The mandatory timelock delay begins.

### Step 7: Execute Proposal
Once the timelock delay has expired:
```bash
cast send $GOVERNOR_GENERAL \
  "execute(uint256)" \
  $PROPOSAL_ID \
  --rpc-url $RPC_URL \
  --private-key $ANY_KEY
```
The `TimelockController` triggers all payload calls on-chain. State becomes `ProposalStage.Executed`.

---

## 5. Emergency Procedures & Administrative Safeguards

### Canceling a Proposal
Before a proposal is executed, the original proposer or the contract owner can cancel it:
```bash
cast send $GOVERNOR_GENERAL \
  "cancel(uint256)" \
  $PROPOSAL_ID \
  --rpc-url $RPC_URL \
  --private-key $PROPOSER_OR_OWNER_KEY
```

### Timelock Emergency Veto
If a malicious proposal manages to pass voting, the Timelock Admin (or Security Council multisig) can cancel the queued transaction directly on the Timelock before the delay matures.
