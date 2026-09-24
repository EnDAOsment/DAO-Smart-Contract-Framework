// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1155TokenUpgradeable} from "contracts/MemberToken.sol";
import {ApprovalGovernor} from "contracts/ApprovalGovernor.sol";
import {QuadraticGovernor} from "contracts/QuadraticGovernor.sol";
import {GovernorGeneral} from "contracts/GovernorGeneral.sol";
import {ICrsManager} from "contracts/ICrsManager.sol";
import {MockTarget} from "./mocks/MockTarget.sol";

contract MockSnapshotCrsManager is ICrsManager {
    mapping(address => mapping(uint256 => uint256)) private _currentScores;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _pastScores;

    function setCrs(address account, uint256 tokenId, uint256 score) external {
        _currentScores[account][tokenId] = score;
    }

    function setPastCrs(address account, uint256 tokenId, uint256 timepoint, uint256 score) external {
        _pastScores[account][tokenId][timepoint] = score;
    }

    function getCrs(address account, uint256 tokenId) external view override returns (uint256) {
        return _currentScores[account][tokenId];
    }

    function getPastCrs(address account, uint256 tokenId, uint256 timepoint) external view override returns (uint256) {
        uint256 past = _pastScores[account][tokenId][timepoint];
        return past > 0 ? past : _currentScores[account][tokenId];
    }
}

contract AdvancedGovernanceFeaturesTest is Test {
    ERC1155TokenUpgradeable public memberToken;
    MockSnapshotCrsManager public crsManager;
    TimelockControllerUpgradeable public timelock;
    ApprovalGovernor public approvalGov;
    QuadraticGovernor public quadraticGov;
    GovernorGeneral public governorGeneral;
    MockTarget public target;

    address public admin = address(0xAD);
    uint256 public alicePrivateKey = 0xA11CE;
    address public alice;
    address public relayer = address(0x999);

    uint256 public constant BADGE_ID = 1;

    function setUp() public {
        vm.roll(100);
        alice = vm.addr(alicePrivateKey);

        // 1. Deploy MemberToken proxy
        address tokenImpl = address(new ERC1155TokenUpgradeable());
        bytes memory tokenInit = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (admin, admin, admin, "https://api.daoframework.io/token/{id}.json")
        );
        memberToken = ERC1155TokenUpgradeable(address(new ERC1967Proxy(tokenImpl, tokenInit)));

        // 2. Deploy CRS Manager
        crsManager = new MockSnapshotCrsManager();

        // 3. Deploy Timelock proxy
        address timelockImpl = address(new TimelockControllerUpgradeable());
        address[] memory emptyAddresses = new address[](0);
        bytes memory timelockInit = abi.encodeCall(
            TimelockControllerUpgradeable.initialize,
            (1 days, emptyAddresses, emptyAddresses, address(this))
        );
        timelock = TimelockControllerUpgradeable(payable(address(new ERC1967Proxy(timelockImpl, timelockInit))));

        // 4. Deploy ApprovalGovernor proxy
        address approvalImpl = address(new ApprovalGovernor());
        bytes memory approvalInit = abi.encodeCall(
            ApprovalGovernor.initialize,
            (address(this), address(memberToken), address(crsManager), 10e18)
        );
        approvalGov = ApprovalGovernor(address(new ERC1967Proxy(approvalImpl, approvalInit)));

        // 5. Deploy QuadraticGovernor proxy
        address quadraticImpl = address(new QuadraticGovernor());
        bytes memory quadraticInit = abi.encodeCall(
            QuadraticGovernor.initialize,
            (address(this), address(memberToken), address(crsManager), 5)
        );
        quadraticGov = QuadraticGovernor(address(new ERC1967Proxy(quadraticImpl, quadraticInit)));

        // 6. Deploy GovernorGeneral proxy
        address generalImpl = address(new GovernorGeneral());
        bytes memory generalInit = abi.encodeCall(
            GovernorGeneral.initialize,
            (
                address(memberToken),
                address(approvalGov),
                address(quadraticGov),
                payable(address(timelock)),
                1,      // votingDelay: 1 block
                50,     // approvalPeriod: 50 blocks
                50,     // quadraticPeriod: 50 blocks
                1,      // proposalThreshold: 1 token
                BADGE_ID
            )
        );
        governorGeneral = GovernorGeneral(address(new ERC1967Proxy(generalImpl, generalInit)));

        // 7. Wire permissions
        approvalGov.setGovernorGeneral(address(governorGeneral));
        quadraticGov.setGovernorGeneral(address(governorGeneral));

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governorGeneral));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governorGeneral));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        // 8. Mint badges and set CRS at block 100
        vm.prank(admin);
        memberToken.mint(alice, BADGE_ID, 10, "");

        crsManager.setCrs(alice, BADGE_ID, 100e18); // 100 CRS => 10,000 max credits

        target = new MockTarget();
        vm.deal(alice, 100 ether);

        // Advance block so checkpoint at block 100 is accessible
        vm.roll(110);
    }

    function _createProposal(string memory desc) internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(alice);
        return governorGeneral.propose(targets, values, calldatas, desc);
    }

    // ==========================================
    // 1. EIP-712 Gasless Voting Tests
    // ==========================================

    function test_CastApprovalVoteBySig_Success() public {
        uint256 proposalId = _createProposal("EIP712 Approval Proposal");

        vm.roll(112); // Voting active (start=111, end=161)

        // Construct EIP-712 struct hash
        uint256 nonce = governorGeneral.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(
                governorGeneral.APPROVAL_VOTE_TYPEHASH(),
                proposalId,
                uint8(1),
                BADGE_ID,
                alice,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governorGeneral.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        // Relayer submits vote for Alice gaslessly
        vm.prank(relayer);
        governorGeneral.castApprovalVoteBySig(proposalId, 1, BADGE_ID, alice, v, r, s);

        assertTrue(approvalGov.hasVoted(proposalId, alice));
        assertEq(governorGeneral.nonces(alice), nonce + 1);
    }

    function test_CastQuadraticVoteBySig_Success() public {
        uint256 proposalId = _createProposal("EIP712 Quadratic Proposal");

        // Pass Stage 1
        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);

        vm.roll(162);
        governorGeneral.advanceToQuadratic(proposalId);

        // Sign Stage 2 Quadratic Vote
        uint256 creditsToSpend = 100; // sqrt(100) = 10 votes
        uint256 nonce = governorGeneral.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(
                governorGeneral.QUADRATIC_VOTE_TYPEHASH(),
                proposalId,
                uint8(1),
                creditsToSpend,
                BADGE_ID,
                alice,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governorGeneral.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        // Relayer submits vote for Alice gaslessly
        vm.roll(163);
        vm.prank(relayer);
        governorGeneral.castQuadraticVoteBySig(proposalId, 1, creditsToSpend, BADGE_ID, alice, v, r, s);

        assertTrue(quadraticGov.hasVoted(proposalId, alice));
        assertEq(quadraticGov.getSpentCredits(proposalId, alice), creditsToSpend);
        (uint256 forVotes, , ) = quadraticGov.getVotes(proposalId);
        assertEq(forVotes, 10);
    }

    function test_CastVoteBySig_RevertReplay() public {
        uint256 proposalId = _createProposal("Replay Proposal");
        vm.roll(112);

        uint256 nonce = governorGeneral.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(
                governorGeneral.APPROVAL_VOTE_TYPEHASH(),
                proposalId,
                uint8(1),
                BADGE_ID,
                alice,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governorGeneral.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        vm.prank(relayer);
        governorGeneral.castApprovalVoteBySig(proposalId, 1, BADGE_ID, alice, v, r, s);

        // Replay submission reverts
        vm.prank(relayer);
        vm.expectRevert(GovernorGeneral.InvalidSignature.selector);
        governorGeneral.castApprovalVoteBySig(proposalId, 1, BADGE_ID, alice, v, r, s);
    }

    // ==========================================
    // 2. Epoch-Based Batched Bounded Rationality Tests
    // ==========================================

    function test_EpochBudget_SharedAcrossProposals() public {
        // Alice max credits = 10,000 for Epoch 1
        uint256 p1 = _createProposal("Proposal A in Epoch 1");
        uint256 p2 = _createProposal("Proposal B in Epoch 1");

        // Pass Stage 1 for both
        vm.roll(112);
        vm.startPrank(alice);
        governorGeneral.castApprovalVote(p1, 1, BADGE_ID);
        governorGeneral.castApprovalVote(p2, 1, BADGE_ID);
        vm.stopPrank();

        vm.roll(162);
        governorGeneral.advanceToQuadratic(p1);
        governorGeneral.advanceToQuadratic(p2);

        // Spend 6,000 credits on Proposal 1
        vm.roll(163);
        vm.prank(alice);
        governorGeneral.castQuadraticVote(p1, 1, 6000, BADGE_ID);

        // Attempting to spend 5,000 on Proposal 2 exceeds epoch budget of 10,000 (6000 + 5000 = 11000 > 10000)
        vm.prank(alice);
        vm.expectRevert(QuadraticGovernor.InsufficientVotingCredits.selector);
        governorGeneral.castQuadraticVote(p2, 1, 5000, BADGE_ID);

        // Spending 4,000 credits on Proposal 2 succeeds (6000 + 4000 = 10000 <= 10000)
        vm.prank(alice);
        governorGeneral.castQuadraticVote(p2, 1, 4000, BADGE_ID);

        assertEq(quadraticGov.epochSpentCredits(1, alice), 10000);
    }

    function test_EpochAdvance_ResetsBudgetForNewProposals() public {
        uint256 p1 = _createProposal("Proposal Epoch 1");
        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(p1, 1, BADGE_ID);
        vm.roll(162);
        governorGeneral.advanceToQuadratic(p1);

        // Alice exhausts 10,000 credits in Epoch 1
        vm.roll(163);
        vm.prank(alice);
        governorGeneral.castQuadraticVote(p1, 1, 10000, BADGE_ID);
        assertEq(quadraticGov.epochSpentCredits(1, alice), 10000);

        // Advance to Epoch 2
        governorGeneral.advanceEpoch();
        assertEq(governorGeneral.currentEpoch(), 2);

        // Proposal 2 created in Epoch 2
        vm.roll(170);
        uint256 p2 = _createProposal("Proposal Epoch 2");
        vm.roll(172);
        vm.prank(alice);
        governorGeneral.castApprovalVote(p2, 1, BADGE_ID);
        vm.roll(222);
        governorGeneral.advanceToQuadratic(p2);

        // Alice now has a fresh 10,000 credits in Epoch 2!
        vm.roll(223);
        vm.prank(alice);
        governorGeneral.castQuadraticVote(p2, 1, 10000, BADGE_ID);
        assertEq(quadraticGov.epochSpentCredits(2, alice), 10000);
    }

    // ==========================================
    // 3. Snapshot Reputation Immunity Tests
    // ==========================================

    function test_SnapshotReputation_ImmuneToMidVoteScoreBoost() public {
        // Proposal created at block 110: voteStart = 111
        // Past snapshot timepoint for CRS lookup is 111
        crsManager.setPastCrs(alice, BADGE_ID, 111, 10e18);

        uint256 proposalId = _createProposal("Snapshot Test Proposal");

        // After proposal creation at block 110, Alice's current score is boosted 100x to 1000e18
        crsManager.setCrs(alice, BADGE_ID, 1000e18);

        vm.roll(112);
        // Stage 1 vote: weight should be snapshot weight 10e18, NOT boosted 1000e18!
        vm.prank(alice);
        uint256 weight = governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);
        assertEq(weight, 10e18);

        vm.roll(162);
        governorGeneral.advanceToQuadratic(proposalId);

        // Snapshot for Quadratic is quadraticStart (162)
        crsManager.setPastCrs(alice, BADGE_ID, 162, 10e18);

        // Stage 2 credit budget: budget should be snapshot budget (1,000 credits), NOT 100,000 credits!
        uint256 budget = quadraticGov.getCreditBudget(alice, BADGE_ID, 162);
        assertEq(budget, 1000); // 10e18 / 1e16 = 1000
    }

    // ==========================================
    // 4. Anti-Spam Proposal Deposit Tests
    // ==========================================

    function test_ProposalDeposit_RefundOnStage1Pass() public {
        governorGeneral.setProposalDeposit(1 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Reverts if deposit not paid
        vm.prank(alice);
        vm.expectRevert(GovernorGeneral.InsufficientProposalDeposit.selector);
        governorGeneral.propose(targets, values, calldatas, "Deposit Required");

        // Propose with required deposit
        uint256 aliceBalBefore = alice.balance;
        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose{value: 1 ether}(targets, values, calldatas, "Deposit Paid");
        assertEq(alice.balance, aliceBalBefore - 1 ether);

        // Pass Stage 1
        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);

        vm.roll(162);
        // Advancing to quadratic refunds the deposit upon passing
        governorGeneral.advanceToQuadratic(proposalId);
        assertEq(alice.balance, aliceBalBefore);
    }

    function test_ProposalDeposit_SlashOnStage1Defeat() public {
        governorGeneral.setProposalDeposit(1 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose{value: 1 ether}(targets, values, calldatas, "Defeated Proposal");

        uint256 timelockBalBefore = address(timelock).balance;

        // No one votes -> Stage 1 fails
        vm.roll(162);
        governorGeneral.advanceToQuadratic(proposalId);

        // Deposit is slashed to Timelock treasury
        assertEq(address(timelock).balance, timelockBalBefore + 1 ether);
    }

    function test_ProposalDeposit_RefundOnCancel() public {
        governorGeneral.setProposalDeposit(1 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        uint256 aliceBalBefore = alice.balance;
        vm.prank(alice);
        governorGeneral.propose{value: 1 ether}(targets, values, calldatas, "Canceled Proposal");

        // Cancel proposal
        vm.prank(alice);
        governorGeneral.cancel(targets, values, calldatas, keccak256(bytes("Canceled Proposal")));

        // Deposit is refunded
        assertEq(alice.balance, aliceBalBefore);
    }

    // ==========================================
    // 5. ERC-6372 Clock Unification Tests
    // ==========================================

    function test_ERC6372_ClockSync() public view {
        assertEq(governorGeneral.clock(), memberToken.clock());
        assertEq(governorGeneral.CLOCK_MODE(), memberToken.CLOCK_MODE());
        assertEq(approvalGov.clock(), memberToken.clock());
        assertEq(approvalGov.CLOCK_MODE(), memberToken.CLOCK_MODE());
        assertEq(quadraticGov.clock(), memberToken.clock());
        assertEq(quadraticGov.CLOCK_MODE(), memberToken.CLOCK_MODE());
    }
}
