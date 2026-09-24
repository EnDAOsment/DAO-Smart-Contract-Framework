// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./MemberToken.sol";
import "./ApprovalGovernor.sol";
import "./QuadraticGovernor.sol";

/**
 * @title GovernorGeneral
 * @dev The Core contract of the DAO framework.
 * Orchestrates multi-stage governance proposals across Approval (Stage 1)
 * and Quadratic (Stage 2) voting modules, interfacing directly with the Timelock.
 * Supports EIP-712 gasless voting, epoch-based credit budgeting, and anti-spam proposal deposits.
 */
contract GovernorGeneral is Initializable, OwnableUpgradeable, UUPSUpgradeable, EIP712Upgradeable {
    enum ProposalStage {
        Pending,
        Approval,
        Quadratic,
        Succeeded,
        Queued,
        Executed,
        Defeated,
        Canceled
    }

    struct Proposal {
        address proposer;
        ProposalStage stage;
        uint48 voteStart;
        uint48 approvalEnd;
        uint48 quadraticStart;
        uint48 quadraticEnd;
        uint256 epochId;
        uint256 deposit;
        bool exists;
        bool canceled;
        bool executed;
    }

    ERC1155TokenUpgradeable public memberToken;
    ApprovalGovernor public approvalGovernor;
    QuadraticGovernor public quadraticGovernor;
    TimelockControllerUpgradeable public timelock;

    uint32 public votingDelay;
    uint32 public approvalPeriod;
    uint32 public quadraticPeriod;
    uint256 public proposalThreshold;
    uint256 public defaultMemberTokenId;

    mapping(uint256 => Proposal) public proposals;

    // Advanced Governance Features
    uint256 public currentEpoch;
    uint256 public epochDuration;
    uint256 public lastEpochTimepoint;
    uint256 public proposalDeposit;
    mapping(address => uint256) public nonces;

    bytes32 public constant APPROVAL_VOTE_TYPEHASH = keccak256(
        "ApprovalVote(uint256 proposalId,uint8 support,uint256 tokenId,address voter,uint256 nonce)"
    );
    bytes32 public constant QUADRATIC_VOTE_TYPEHASH = keccak256(
        "QuadraticVote(uint256 proposalId,uint8 support,uint256 creditsToSpend,uint256 tokenId,address voter,uint256 nonce)"
    );

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint48 voteStart,
        uint48 approvalEnd,
        string description
    );
    event ProposalStageAdvanced(uint256 indexed proposalId, ProposalStage newStage);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event ProposalDepositRefunded(uint256 indexed proposalId, address indexed proposer, uint256 amount);
    event ProposalDepositSlashed(uint256 indexed proposalId, address indexed treasury, uint256 amount);
    event EpochAdvanced(uint256 indexed newEpoch, uint256 timepoint);
    event ProposalDepositUpdated(uint256 oldDeposit, uint256 newDeposit);
    event EpochDurationUpdated(uint256 oldDuration, uint256 newDuration);

    error ProposalAlreadyExists();
    error ProposalDoesNotExist();
    error InsufficientProposerVotes();
    error InvalidProposalStage(ProposalStage expected, ProposalStage actual);
    error VotingNotActive();
    error StageCriteriaNotMet();
    error OnlyProposerOrTimelock();
    error InsufficientProposalDeposit();
    error DepositRefundFailed();
    error DepositSlashFailed();
    error InvalidSignature();
    error EpochNotElapsed();
    error Unauthorized();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _memberToken,
        address _approvalGovernor,
        address _quadraticGovernor,
        address payable _timelock,
        uint32 _votingDelay,
        uint32 _approvalPeriod,
        uint32 _quadraticPeriod,
        uint256 _proposalThreshold,
        uint256 _defaultMemberTokenId
    ) public initializer {
        __Ownable_init(msg.sender);
        __EIP712_init("GovernorGeneral", "1");

        memberToken = ERC1155TokenUpgradeable(_memberToken);
        approvalGovernor = ApprovalGovernor(_approvalGovernor);
        quadraticGovernor = QuadraticGovernor(_quadraticGovernor);
        timelock = TimelockControllerUpgradeable(_timelock);

        votingDelay = _votingDelay;
        approvalPeriod = _approvalPeriod;
        quadraticPeriod = _quadraticPeriod;
        proposalThreshold = _proposalThreshold;
        defaultMemberTokenId = _defaultMemberTokenId;

        currentEpoch = 1;
        lastEpochTimepoint = clock();
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    /**
     * @notice Sets required deposit to submit proposals.
     */
    function setProposalDeposit(uint256 _proposalDeposit) external onlyOwner {
        uint256 old = proposalDeposit;
        proposalDeposit = _proposalDeposit;
        emit ProposalDepositUpdated(old, _proposalDeposit);
    }

    /**
     * @notice Sets duration for fiscal epochs.
     */
    function setEpochDuration(uint256 _epochDuration) external onlyOwner {
        uint256 old = epochDuration;
        epochDuration = _epochDuration;
        emit EpochDurationUpdated(old, _epochDuration);
    }

    /**
     * @notice Advances the governance epoch, resetting quadratic credit allocations across new proposals.
     */
    function advanceEpoch() public returns (uint256) {
        if (epochDuration > 0) {
            if (clock() < lastEpochTimepoint + epochDuration && msg.sender != owner()) {
                revert EpochNotElapsed();
            }
        } else if (msg.sender != owner()) {
            revert Unauthorized();
        }

        currentEpoch++;
        lastEpochTimepoint = clock();
        emit EpochAdvanced(currentEpoch, lastEpochTimepoint);
        return currentEpoch;
    }

    /**
     * @notice Creates a new proposal entering Stage 1 (Approval).
     * Accepts optional proposal deposit as anti-spam collateral.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public payable returns (uint256) {
        if (msg.value < proposalDeposit) revert InsufficientProposalDeposit();

        // Enforce proposal threshold
        uint48 current = clock();
        uint48 pastTimepoint = current > 0 ? current - 1 : 0;
        uint256 proposerBalance = memberToken.getPastBalanceOf(msg.sender, defaultMemberTokenId, pastTimepoint);
        if (proposerBalance < proposalThreshold) {
            revert InsufficientProposerVotes();
        }

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        if (proposals[proposalId].exists) revert ProposalAlreadyExists();

        uint48 start = SafeCast.toUint48(current + votingDelay);
        uint48 end = SafeCast.toUint48(start + approvalPeriod);

        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            stage: ProposalStage.Approval,
            voteStart: start,
            approvalEnd: end,
            quadraticStart: 0,
            quadraticEnd: 0,
            epochId: currentEpoch,
            deposit: msg.value,
            exists: true,
            canceled: false,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, targets, values, calldatas, start, end, description);
        return proposalId;
    }

    /**
     * @notice Internal handler for Stage 1 approval vote.
     */
    function _castApprovalVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        uint256 tokenId
    ) internal returns (uint256) {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (state(proposalId) != ProposalStage.Approval) {
            revert InvalidProposalStage(ProposalStage.Approval, state(proposalId));
        }

        return approvalGovernor.castVote(proposalId, voter, support, tokenId, p.voteStart);
    }

    /**
     * @notice Casts an Approval vote directly during Stage 1.
     */
    function castApprovalVote(
        uint256 proposalId,
        uint8 support,
        uint256 tokenId
    ) public returns (uint256) {
        return _castApprovalVote(proposalId, msg.sender, support, tokenId);
    }

    /**
     * @notice Casts an Approval vote via EIP-712 signature (gasless meta-transaction).
     */
    function castApprovalVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint256 tokenId,
        address voter,
        bytes memory signature
    ) public returns (uint256) {
        bytes32 structHash = keccak256(
            abi.encode(APPROVAL_VOTE_TYPEHASH, proposalId, support, tokenId, voter, nonces[voter]++)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(voter, digest, signature)) {
            revert InvalidSignature();
        }

        return _castApprovalVote(proposalId, voter, support, tokenId);
    }

    /**
     * @notice Overload for castApprovalVoteBySig accepting (v, r, s) ECDSA components.
     */
    function castApprovalVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint256 tokenId,
        address voter,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        return castApprovalVoteBySig(proposalId, support, tokenId, voter, abi.encodePacked(r, s, v));
    }

    /**
     * @notice Permissionlessly advances proposal from Approval to Quadratic stage if passed.
     * Manages anti-spam deposit: refunds on pass, slashes to Timelock on failure.
     */
    function advanceToQuadratic(uint256 proposalId) public {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (clock() <= p.approvalEnd) revert VotingNotActive();
        if (p.stage != ProposalStage.Approval) {
            revert InvalidProposalStage(ProposalStage.Approval, p.stage);
        }

        if (approvalGovernor.hasPassed(proposalId)) {
            p.stage = ProposalStage.Quadratic;
            uint48 current = clock();
            p.quadraticStart = current;
            p.quadraticEnd = SafeCast.toUint48(current + quadraticPeriod);
            emit ProposalStageAdvanced(proposalId, ProposalStage.Quadratic);

            // Refund proposal deposit upon Stage 1 consensus (Checks-Effects-Interactions)
            if (p.deposit > 0) {
                uint256 depositRefund = p.deposit;
                p.deposit = 0;
                emit ProposalDepositRefunded(proposalId, p.proposer, depositRefund);
                (bool success, ) = p.proposer.call{value: depositRefund}("");
                if (!success) revert DepositRefundFailed();
            }
        } else {
            p.stage = ProposalStage.Defeated;
            emit ProposalStageAdvanced(proposalId, ProposalStage.Defeated);

            // Slash deposit to Timelock treasury if proposal failed Stage 1
            if (p.deposit > 0) {
                uint256 depositSlashed = p.deposit;
                p.deposit = 0;
                emit ProposalDepositSlashed(proposalId, address(timelock), depositSlashed);
                (bool success, ) = address(timelock).call{value: depositSlashed}("");
                if (!success) revert DepositSlashFailed();
            }
        }
    }

    /**
     * @notice Internal handler for Stage 2 quadratic vote.
     */
    function _castQuadraticVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId
    ) internal returns (uint256) {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (state(proposalId) != ProposalStage.Quadratic) {
            revert InvalidProposalStage(ProposalStage.Quadratic, state(proposalId));
        }

        return quadraticGovernor.castVote(
            proposalId,
            voter,
            support,
            creditsToSpend,
            tokenId,
            p.quadraticStart,
            p.epochId
        );
    }

    /**
     * @notice Casts a Quadratic vote directly during Stage 2.
     */
    function castQuadraticVote(
        uint256 proposalId,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId
    ) public returns (uint256) {
        return _castQuadraticVote(proposalId, msg.sender, support, creditsToSpend, tokenId);
    }

    /**
     * @notice Casts a Quadratic vote via EIP-712 signature (gasless meta-transaction).
     */
    function castQuadraticVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId,
        address voter,
        bytes memory signature
    ) public returns (uint256) {
        bytes32 structHash = keccak256(
            abi.encode(
                QUADRATIC_VOTE_TYPEHASH,
                proposalId,
                support,
                creditsToSpend,
                tokenId,
                voter,
                nonces[voter]++
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(voter, digest, signature)) {
            revert InvalidSignature();
        }

        return _castQuadraticVote(proposalId, voter, support, creditsToSpend, tokenId);
    }

    /**
     * @notice Overload for castQuadraticVoteBySig accepting (v, r, s) ECDSA components.
     */
    function castQuadraticVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId,
        address voter,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        return castQuadraticVoteBySig(
            proposalId,
            support,
            creditsToSpend,
            tokenId,
            voter,
            abi.encodePacked(r, s, v)
        );
    }

    /**
     * @notice Finalizes quadratic voting stage.
     */
    function finalizeQuadratic(uint256 proposalId) public {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (p.stage != ProposalStage.Quadratic) {
            revert InvalidProposalStage(ProposalStage.Quadratic, p.stage);
        }
        if (clock() <= p.quadraticEnd) revert VotingNotActive();

        if (quadraticGovernor.hasPassed(proposalId)) {
            p.stage = ProposalStage.Succeeded;
            emit ProposalStageAdvanced(proposalId, ProposalStage.Succeeded);
        } else {
            p.stage = ProposalStage.Defeated;
            emit ProposalStageAdvanced(proposalId, ProposalStage.Defeated);
        }
    }

    /**
     * @notice Queues a succeeded proposal into the Timelock.
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();

        // Auto-finalize if stage is still Quadratic but deadline elapsed
        if (p.stage == ProposalStage.Quadratic && clock() > p.quadraticEnd) {
            finalizeQuadratic(proposalId);
        }

        if (p.stage != ProposalStage.Succeeded) {
            revert InvalidProposalStage(ProposalStage.Succeeded, p.stage);
        }

        uint256 delay = timelock.getMinDelay();
        p.stage = ProposalStage.Queued;
        emit ProposalQueued(proposalId, block.timestamp + delay);

        timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);
        return proposalId;
    }

    /**
     * @notice Executes a queued proposal from the Timelock.
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (p.stage != ProposalStage.Queued) {
            revert InvalidProposalStage(ProposalStage.Queued, p.stage);
        }

        p.executed = true;
        p.stage = ProposalStage.Executed;
        emit ProposalExecuted(proposalId);

        timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, descriptionHash);
        return proposalId;
    }

    /**
     * @notice Cancels a proposal before execution.
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (msg.sender != p.proposer && msg.sender != owner() && msg.sender != address(timelock)) {
            revert OnlyProposerOrTimelock();
        }
        if (p.executed || p.stage == ProposalStage.Executed) revert StageCriteriaNotMet();

        p.canceled = true;
        p.stage = ProposalStage.Canceled;
        emit ProposalCanceled(proposalId);

        // Refund deposit if canceled
        if (p.deposit > 0) {
            uint256 depositRefund = p.deposit;
            p.deposit = 0;
            emit ProposalDepositRefunded(proposalId, p.proposer, depositRefund);
            (bool success, ) = p.proposer.call{value: depositRefund}("");
            if (!success) revert DepositRefundFailed();
        }

        // If queued in timelock, cancel timelock operations
        bytes32 id = timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
        if (timelock.isOperation(id)) {
            timelock.cancel(id);
        }

        return proposalId;
    }

    /**
     * @notice Returns the current ProposalStage for a proposal.
     */
    function state(uint256 proposalId) public view returns (ProposalStage) {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (p.canceled) return ProposalStage.Canceled;
        if (p.executed) return ProposalStage.Executed;

        if (p.stage == ProposalStage.Approval) {
            uint48 current = clock();
            if (current < p.voteStart) {
                return ProposalStage.Pending;
            } else if (current <= p.approvalEnd) {
                return ProposalStage.Approval;
            } else {
                return approvalGovernor.hasPassed(proposalId) ? ProposalStage.Approval : ProposalStage.Defeated;
            }
        }

        if (p.stage == ProposalStage.Quadratic) {
            uint48 current = clock();
            if (current <= p.quadraticEnd) {
                return ProposalStage.Quadratic;
            } else {
                return quadraticGovernor.hasPassed(proposalId) ? ProposalStage.Succeeded : ProposalStage.Defeated;
            }
        }

        return p.stage;
    }

    /**
     * @notice Current timepoint synced from MemberToken with safe fallback.
     */
    function clock() public view virtual returns (uint48) {
        if (address(memberToken).code.length > 0) {
            try memberToken.clock() returns (uint48 timepoint) {
                return timepoint;
            } catch {
                return SafeCast.toUint48(block.number);
            }
        }
        return SafeCast.toUint48(block.number);
    }

    /**
     * @notice Description of the clock mode synced from MemberToken with safe fallback.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        if (address(memberToken).code.length > 0) {
            try memberToken.CLOCK_MODE() returns (string memory mode) {
                return mode;
            } catch {
                return "mode=blocknumber&finality=finalized";
            }
        }
        return "mode=blocknumber&finality=finalized";
    }

    /**
     * @notice Returns EIP-712 domain separator.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[44] private __gap;
}
