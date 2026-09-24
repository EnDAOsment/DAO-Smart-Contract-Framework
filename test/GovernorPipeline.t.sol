// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "contracts/MemberToken.sol";
import "contracts/ApprovalGovernor.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/GovernorGeneral.sol";
import "test/mocks/MockCrsManager.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockTarget {
    uint256 public value;
    event TargetExecuted(uint256 newValue);

    function setValue(uint256 newValue) external payable {
        value = newValue;
        emit TargetExecuted(newValue);
    }
}

contract GovernorPipelineTest is Test {
    ERC1155TokenUpgradeable public memberToken;
    ApprovalGovernor public approvalGov;
    QuadraticGovernor public quadraticGov;
    GovernorGeneral public governorGeneral;
    TimelockControllerUpgradeable public timelock;
    MockCrsManager public crsManager;
    MockTarget public target;

    address public admin = address(0xAD);
    address public alice = address(0xAA);
    address public bob = address(0xBB);
    address public charlie = address(0xCC);

    uint256 public constant BADGE_ID = 1;

    function setUp() public {
        vm.roll(100);

        // 1. Deploy MemberToken proxy
        address tokenImpl = address(new ERC1155TokenUpgradeable());
        bytes memory tokenInit = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (admin, admin, admin, "https://api.daoframework.io/token/{id}.json")
        );
        memberToken = ERC1155TokenUpgradeable(address(new ERC1967Proxy(tokenImpl, tokenInit)));

        // 2. Deploy CRS Manager
        crsManager = new MockCrsManager();

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
            (address(this), address(memberToken), address(crsManager), 20)
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

        // 8. Mint badges and set CRS
        vm.startPrank(admin);
        memberToken.mint(alice, BADGE_ID, 10, "");
        memberToken.mint(bob, BADGE_ID, 10, "");
        memberToken.mint(charlie, BADGE_ID, 10, "");
        vm.stopPrank();

        crsManager.setCrs(alice, BADGE_ID, 100e18); // 100 CRS => 1,000,000 max credits
        crsManager.setCrs(bob, BADGE_ID, 50e18);   // 50 CRS => 500,000 max credits
        crsManager.setCrs(charlie, BADGE_ID, 10e18); // 10 CRS => 100,000 max credits

        target = new MockTarget();
    }

    function test_CreateProposal_Success() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        string memory desc = "Proposal #1: Set Target to 42";

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, desc);

        assertTrue(proposalId != 0);
        assertEq(uint256(governorGeneral.state(proposalId)), uint256(GovernorGeneral.ProposalStage.Pending));
    }

    function test_CreateProposal_RevertInsufficientVotes() public {
        vm.roll(110);
        address nonMember = address(0xDEAD);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(nonMember);
        vm.expectRevert(GovernorGeneral.InsufficientProposerVotes.selector);
        governorGeneral.propose(targets, values, calldatas, "Invalid Proposal");
    }

    function test_CastApprovalVote_Success() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, "Proposal 1");

        // Advance 2 blocks past votingDelay
        vm.roll(112);
        assertEq(uint256(governorGeneral.state(proposalId)), uint256(GovernorGeneral.ProposalStage.Approval));

        // Alice votes FOR (support = 1)
        vm.prank(alice);
        uint256 weight = governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);
        assertEq(weight, 100e18);

        assertTrue(approvalGov.hasVoted(proposalId, alice));
        (uint256 forVotes, uint256 againstVotes, ) = approvalGov.getVotes(proposalId);
        assertEq(forVotes, 100e18);
        assertEq(againstVotes, 0);
    }

    function test_CastApprovalVote_RevertDuplicateVote() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, "Proposal 1");

        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);

        // Second vote must revert
        vm.prank(alice);
        vm.expectRevert(ApprovalGovernor.AlreadyVoted.selector);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);
    }

    function test_AdvanceToQuadratic_Success() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, "Proposal 1");

        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID); // 100e18 >= 10e18 quorum

        // Roll past approvalPeriod (111 + 50 = 161)
        vm.roll(165);

        // Advance stage to Quadratic
        governorGeneral.advanceToQuadratic(proposalId);
        assertEq(uint256(governorGeneral.state(proposalId)), uint256(GovernorGeneral.ProposalStage.Quadratic));
    }

    function test_AdvanceToQuadratic_DefeatedIfQuorumNotMet() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, "Proposal Defeated");

        // Roll past approvalPeriod without votes
        vm.roll(165);

        governorGeneral.advanceToQuadratic(proposalId);
        assertEq(uint256(governorGeneral.state(proposalId)), uint256(GovernorGeneral.ProposalStage.Defeated));
    }

    function test_CastQuadraticVote_Success() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, "Proposal 1");

        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);

        vm.roll(165);
        governorGeneral.advanceToQuadratic(proposalId);

        // Alice spends 10,000 credits -> votes = sqrt(10,000) = 100
        vm.roll(166);
        vm.prank(alice);
        uint256 votesCast = governorGeneral.castQuadraticVote(proposalId, 1, 10000, BADGE_ID);

        assertEq(votesCast, 100);
        assertEq(quadraticGov.getSpentCredits(proposalId, alice), 10000);

        (uint256 forVotes, , ) = quadraticGov.getVotes(proposalId);
        assertEq(forVotes, 100);
    }

    function test_CastQuadraticVote_RevertInsufficientCredits() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, "Proposal 1");

        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);

        vm.roll(165);
        governorGeneral.advanceToQuadratic(proposalId);

        // Charlie has 10 CRS => budget is 10e18 / 1e14 = 100,000 credits
        // Charlie tries to spend 200,000 credits
        vm.roll(166);
        vm.prank(charlie);
        vm.expectRevert(QuadraticGovernor.InsufficientVotingCredits.selector);
        governorGeneral.castQuadraticVote(proposalId, 1, 200000, BADGE_ID);
    }

    function test_FullGovernanceLifecycle_ApprovalToQuadraticToTimelock() public {
        vm.roll(110);
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 888);
        string memory desc = "Proposal #888: Execute on Timelock";
        bytes32 descHash = keccak256(bytes(desc));

        // 1. Propose
        vm.prank(alice);
        uint256 proposalId = governorGeneral.propose(targets, values, calldatas, desc);

        // 2. Stage 1: Approval Voting
        vm.roll(112);
        vm.prank(alice);
        governorGeneral.castApprovalVote(proposalId, 1, BADGE_ID);

        // 3. Advance to Stage 2: Quadratic
        vm.roll(165);
        governorGeneral.advanceToQuadratic(proposalId);

        // 4. Stage 2: Quadratic Voting
        vm.roll(170);
        vm.prank(alice);
        governorGeneral.castQuadraticVote(proposalId, 1, 2500, BADGE_ID); // sqrt(2500) = 50 votes (quorum = 20)

        // 5. Finalize Quadratic & Queue into Timelock
        vm.roll(220); // quadratic deadline elapsed (165 + 50 = 215)
        governorGeneral.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governorGeneral.state(proposalId)), uint256(GovernorGeneral.ProposalStage.Queued));

        // 6. Wait for Timelock Min Delay (1 day)
        vm.warp(block.timestamp + 1 days + 1);

        // 7. Execute on Timelock
        governorGeneral.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governorGeneral.state(proposalId)), uint256(GovernorGeneral.ProposalStage.Executed));

        // Verify target contract received the executed call
        assertEq(target.value(), 888);
    }
}
