# Federated Agency DAO Integration & Customization Guide

## 1. Concept: The Federated Agency Model

In the EnDAOsment governance framework, an **Organization** or **Independent Agency** is an autonomous sub-ecosystem (such as a working group, regional chapter, specialized guild, or external enterprise partner) that operates with its own:
- Distinct membership credentials (ERC-1155 Soulbound Token badges).
- Autonomous multi-stage governance rules (Stage 1 Approval + Stage 2 Quadratic).
- Dedicated execution Timelock and treasury.
- Customized Contribution Reputation Score (CRS) engine.

Rather than redeploying hundreds of kilobytes of bytecode for every agency, the `ContractsFactory` instantiates lightweight, gas-efficient ERC-1967 proxy clones that point to canonical, audited implementations.

---

## 2. Deploying an Agency DAO

### Configuration Struct
An agency initiates deployment by preparing an `AgencyDAOConfig` struct:

```solidity
struct AgencyDAOConfig {
    address agencyAdmin;         // Address granted administrative ownership & minting roles
    string tokenUri;             // Metadata URI for ERC-1155 member badges (e.g. "https://api.agency.org/badges/{id}.json")
    address crsManager;          // Contract address implementing ICrsManager for reputation lookups
    uint256 approvalQuorum;      // Minimum Stage 1 CRS approval score required to pass
    uint256 quadraticQuorum;     // Minimum Stage 2 quadratic votes required to pass
    uint32 timelockMinDelay;     // Timelock execution delay in seconds (e.g. 172800 for 2 days)
    uint32 votingDelay;          // Delay in blocks between proposal submission and voting start
    uint32 approvalPeriod;       // Duration of Stage 1 Approval voting in blocks
    uint32 quadraticPeriod;      // Duration of Stage 2 Quadratic voting in blocks
    uint256 proposalThreshold;   // Minimum member badge balance required to create proposals
    uint256 defaultMemberTokenId;// Default ERC-1155 token ID representing agency membership
}
```

### Foundry Script Example
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "contracts/ContractsFactory.sol";

contract DeployMyAgency is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("AGENCY_DEPLOYER_KEY");
        address agencyAdmin = vm.addr(deployerKey);
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");

        vm.startBroadcast(deployerKey);

        ContractsFactory factory = ContractsFactory(factoryAddress);

        ContractsFactory.AgencyDAOConfig memory config = ContractsFactory.AgencyDAOConfig({
            agencyAdmin: agencyAdmin,
            tokenUri: "https://myagency.org/badges/{id}.json",
            crsManager: address(0xYourCrsManagerAddress),
            approvalQuorum: 100e18,       // 100 total CRS score
            quadraticQuorum: 250,         // 250 quadratic votes
            timelockMinDelay: 2 days,     // 48 hour execution delay
            votingDelay: 10,              // 10 blocks before voting begins
            approvalPeriod: 50400,        // ~1 week at 12s/block
            quadraticPeriod: 50400,       // ~1 week at 12s/block
            proposalThreshold: 1,         // Must hold at least 1 membership badge
            defaultMemberTokenId: 1       // ID 1 represents general membership
        });

        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployAgencyDAO(config);

        console.log("MemberToken Proxy:       ", deployment.memberToken);
        console.log("Timelock Proxy:          ", deployment.timelock);
        console.log("ApprovalGovernor Proxy:  ", deployment.approvalGovernor);
        console.log("QuadraticGovernor Proxy: ", deployment.quadraticGovernor);
        console.log("GovernorGeneral Proxy:   ", deployment.governorGeneral);

        vm.stopBroadcast();
    }
}
```

---

## 3. Customizing the Reputation Engine (`ICrsManager`)

The framework decouples reputation calculation from the governance contracts. Any organization can implement custom on-chain or oracle-backed reputation scoring by adhering to the [`ICrsManager`](../contracts/ICrsManager.sol) interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ICrsManager {
    function getCrs(address account, uint256 tokenId) external view returns (uint256);
    function getPastCrs(address account, uint256 tokenId, uint256 timepoint) external view returns (uint256);
}
```

### Reference Implementation: Dynamic Activity-Based CRS
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "contracts/ICrsManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DynamicAgencyCrsManager is ICrsManager, Ownable {
    mapping(address => uint256) public baseReputation;
    mapping(address => uint256) public taskCompletions;

    constructor() Ownable(msg.sender) {}

    function recordActivity(address contributor, uint256 points) external onlyOwner {
        taskCompletions[contributor] += points;
    }

    function getCrs(address account, uint256 /* tokenId */) external view override returns (uint256) {
        // Example: Base reputation + 10x points for completed agency tasks
        return baseReputation[account] + (taskCompletions[account] * 10e18);
    }

    function getPastCrs(address account, uint256 tokenId, uint256 /* timepoint */) external view override returns (uint256) {
        return this.getCrs(account, tokenId);
    }
}
```

---

## 4. Multi-Tier Membership Badges

Because the framework uses **ERC-1155**, an agency can define multiple badge tiers under the same token contract:
- `ID = 1`: **General Member** (Eligible to vote in Stage 1 & 2).
- `ID = 2`: **Core Contributor** (Granted elevated CRS score or proposal initiation rights).
- `ID = 3`: **Working Group Lead / Council Member** (Eligible to submit expedited proposals or emergency vetoes).

To issue badges to new members, the agency admin calls `mint`:
```solidity
ERC1155TokenUpgradeable(memberToken).mint(newMember, 1, 1, "");
```

To revoke membership if a contributor leaves or violates code of conduct:
```solidity
ERC1155TokenUpgradeable(memberToken).burn(departingMember, 1, 1);
```

---

## 5. Agency Roles & Autonomy

When an agency DAO is deployed, `ContractsFactory` automatically establishes the following separation of powers:
1. **Agency Admin**:
   - Holds `DEFAULT_ADMIN_ROLE` and `MINTER_ROLE` on `MemberToken`.
   - Holds `DEFAULT_ADMIN_ROLE` on the `TimelockController`.
   - Owns `GovernorGeneral`, `ApprovalGovernor`, and `QuadraticGovernor`.
2. **Governor General**:
   - Holds `PROPOSER_ROLE` and `CANCELLER_ROLE` on the `TimelockController`.
   - Coordinates proposal lifecycles autonomously.
3. **Contracts Factory**:
   - Holds **0 persistent roles** in the deployed agency DAO.
   - The factory renounces temporary deployment privileges during the finalization step of `deployAgencyDAO`.

---

## 6. Upgrading Your Agency Contracts

Each component proxy can be independently upgraded by the agency's administrator:
- To upgrade `GovernorGeneral`:
  ```solidity
  GovernorGeneral(proxy).upgradeToAndCall(newGovernorGeneralImpl, "");
  ```
- To update the `ICrsManager` address without upgrading bytecode:
  ```solidity
  // Redeploy or update governor general configuration
  ApprovalGovernor(approvalProxy).setQuorumScore(newQuorum);
  QuadraticGovernor(quadraticProxy).setQuadraticQuorum(newQuorum);
  ```

---

## 7. Managing Governance Epochs & Anti-Spam Deposits

Agencies can tune proposal pacing and protect their community from governance spam:

### A. Configuring Anti-Spam Proposal Bonds
To deter spam proposals, set a refundable native token deposit (in wei):
```solidity
// Require 0.1 ETH / native token deposit per proposal
governorGeneral.setProposalDeposit(0.1 ether);
```
- Proposers who achieve Stage 1 consensus receive a **100% refund**.
- Proposals that fail Stage 1 have their deposit **slashed to the agency Timelock**.

### B. Setting Governance Epochs
To constrain voter fatigue and prevent members from having infinite credit allocations across concurrent votes:
```solidity
// Set epoch duration to 30 days (in blocks or seconds depending on clock mode)
governorGeneral.setEpochDuration(30 days);
```
- Members spend from a single cumulative credit budget across all proposals within the epoch.
- When an epoch expires, any community member can call:
```solidity
governorGeneral.advanceEpoch();
```
All members receive a fresh quadratic credit allocation for proposals submitted in the new epoch.

---

## 8. Frontend & Gasless Voting Integration (EIP-712)

Agency frontends can provide gasless voting experiences so DAO members sign votes without paying transaction fees:

```typescript
// 1. Construct EIP-712 Typed Data
const domain = {
  name: "GovernorGeneral",
  version: "1",
  chainId: await signer.getChainId(),
  verifyingContract: governorGeneralAddress
};

const types = {
  ApprovalVote: [
    { name: "proposalId", type: "uint256" },
    { name: "support", type: "uint8" },
    { name: "tokenId", type: "uint256" },
    { name: "voter", type: "address" },
    { name: "nonce", type: "uint256" }
  ]
};

const value = {
  proposalId,
  support: 1, // 1 = For
  tokenId: 1, // Member badge
  voter: await signer.getAddress(),
  nonce: await governorGeneral.nonces(voterAddress)
};

// 2. Member signs off-chain (EIP-712)
const signature = await signer.signTypedData(domain, types, value);

// 3. Agency relayer broadcasts on-chain
await governorGeneralRelayer.castApprovalVoteBySig(
  proposalId,
  1,
  1,
  voterAddress,
  signature
);
```
Works out-of-the-box with Metamask, Coinbase Wallet, Frame, and ERC-1271 multi-sigs (Gnosis Safe).

---

## 9. Deployment Modes: Autonomous UUPS vs. Federated Beacon

`ContractsFactory` provides independent agencies two distinct deployment architectures:

### Mode 1: Autonomous UUPS (`deployAgencyDAO`)
- **Best for**: Completely independent agencies requiring total sovereign isolation from the federal protocol.
- **Mechanism**: Deploys individual ERC-1967 UUPS proxies. The agency administrator owns their own proxy upgrade rights (`onlyOwner` / timelock).
- **Federal Link**: None. Federal protocol upgrades never touch autonomous UUPS instances.

### Mode 2: Federated Beacon (`deployFederatedAgencyDAO`)
- **Best for**: Agencies that want canonical federal improvements and bug fixes propagated automatically, while preserving sovereign rights to override or customize at will.
- **Mechanism**: Deploys [`FederatedBeaconProxy`](../contracts/FederatedBeaconProxy.sol) instances pointing to the Federal Protocol's canonical `UpgradeableBeacon` contracts.

#### Downstream Override & Customization Workflow

If your agency develops a specialized governance rule (e.g. customized quadratic formula, special quorum, or custom badge gating):

```solidity
// 1. Deploy your agency's custom contract
MockCustomStageGovernor customGovernor = new MockCustomStageGovernor("CustomRuleV1");

// 2. As the agencyAdmin, call overrideImplementation on the proxy
FederatedBeaconProxy(payable(deployment.approvalGovernor)).overrideImplementation(address(customGovernor));

// 3. Verify override
bool isOverridden = FederatedBeaconProxy(payable(deployment.approvalGovernor)).isOverridden(); // true
```

While overridden, the agency proxy **ignores upstream federal beacon upgrades** and executes the custom logic exclusively.

#### Restoring the Federal Standard

If the federal protocol incorporates your improvements in a future release and your agency wishes to re-join the federal baseline:

```solidity
// Realign with the Federal Beacon in a single transaction
FederatedBeaconProxy(payable(deployment.approvalGovernor)).resetToFederalBeacon();

// Verify restoration
bool isOverridden = FederatedBeaconProxy(payable(deployment.approvalGovernor)).isOverridden(); // false
```
The proxy immediately resumes executing the latest canonical federal implementation.

