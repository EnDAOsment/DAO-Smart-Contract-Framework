// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./MemberToken.sol";
import "./ICrsManager.sol";
import "./IStageGovernor.sol";

/**
 * @title QuadraticGovernor
 * @dev Governance module for Stage 2: Resource Allocation (Quadratic Voting).
 * Implements bounded rationality via epoch-based credit budgets derived from snapshot CRS.
 * Enforces voting power strictly as V = floor(sqrt(C)).
 */
contract QuadraticGovernor is Initializable, OwnableUpgradeable, UUPSUpgradeable, IStageGovernor {
    struct ProposalVote {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) spentCredits;
    }

    ERC1155TokenUpgradeable public memberToken;
    ICrsManager public crsManager;
    address public governorGeneral;
    uint256 public quadraticQuorum;

    // Minimum baseline voting credits allocated to any badge holder
    uint256 public constant MIN_CREDITS = 100;
    // Scale factor to convert CRS score into quadratic voting credits
    uint256 public constant CREDITS_SCALE = 1e16;

    mapping(uint256 => ProposalVote) private _proposalVotes;
    // epochId => voter => cumulative credits spent across all proposals in this epoch
    mapping(uint256 => mapping(address => uint256)) public epochSpentCredits;

    event QuadraticVoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 creditsSpent,
        uint256 votesCast
    );
    event EpochCreditsSpent(
        uint256 indexed epochId,
        address indexed voter,
        uint256 creditsSpent,
        uint256 totalEpochSpent
    );
    event QuadraticQuorumUpdated(uint256 oldQuadraticQuorum, uint256 newQuadraticQuorum);
    event GovernorGeneralUpdated(address indexed oldGovernorGeneral, address indexed newGovernorGeneral);

    error OnlyGovernorGeneral();
    error AlreadyVoted();
    error NotMember();
    error InvalidVoteChoice();
    error InsufficientVotingCredits();
    error ZeroCreditsSpent();
    error ZeroAddress();

    modifier onlyGovernorGeneral() {
        if (msg.sender != governorGeneral && msg.sender != owner()) {
            revert OnlyGovernorGeneral();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _memberToken,
        address _crsManager,
        uint256 _quadraticQuorum
    ) public initializer {
        if (_owner == address(0) || _memberToken == address(0) || _crsManager == address(0)) {
            revert ZeroAddress();
        }
        __Ownable_init(_owner);

        memberToken = ERC1155TokenUpgradeable(_memberToken);
        crsManager = ICrsManager(_crsManager);
        quadraticQuorum = _quadraticQuorum;
    }

    function setGovernorGeneral(address _governorGeneral) external onlyOwner {
        if (_governorGeneral == address(0)) revert ZeroAddress();
        address old = governorGeneral;
        governorGeneral = _governorGeneral;
        emit GovernorGeneralUpdated(old, _governorGeneral);
    }

    function setQuadraticQuorum(uint256 _quadraticQuorum) external onlyOwner {
        uint256 old = quadraticQuorum;
        quadraticQuorum = _quadraticQuorum;
        emit QuadraticQuorumUpdated(old, _quadraticQuorum);
    }

    /**
     * @notice Returns stage identifier (2 = Quadratic).
     */
    function stageId() external pure override returns (uint8) {
        return 2;
    }

    /**
     * @notice Computes maximum voting credits allocated to a member based on snapshot CRS.
     */
    function getCreditBudget(address voter, uint256 tokenId, uint256 snapshot) public view returns (uint256) {
        uint256 score = crsManager.getPastCrs(voter, tokenId, snapshot);
        if (score == 0) {
            return MIN_CREDITS;
        }
        uint256 calculated = score / CREDITS_SCALE;
        return calculated > MIN_CREDITS ? calculated : MIN_CREDITS;
    }

    /**
     * @notice Backwards-compatible convenience getter using latest block.
     */
    function getCreditBudget(address voter, uint256 tokenId) external view returns (uint256) {
        uint48 current = memberToken.clock();
        uint48 timepoint = current > 0 ? current - 1 : 0;
        return getCreditBudget(voter, tokenId, timepoint);
    }

    /**
     * @notice Casts a quadratic vote for a proposal in Stage 2.
     * Enforces bounded rationality by checking remaining credit budget within the proposal's epoch.
     * @param proposalId The ID of the proposal.
     * @param voter The address of the voter.
     * @param support 0 = Against, 1 = For, 2 = Abstain.
     * @param creditsToSpend Amount of voting credits to spend (V = sqrt(credits)).
     * @param tokenId The ERC1155 member badge token ID.
     * @param snapshot The snapshot block number for balance check.
     * @param epochId The fiscal epoch ID of the proposal.
     */
    function castVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId,
        uint256 snapshot,
        uint256 epochId
    ) external onlyGovernorGeneral returns (uint256) {
        if (support > 2) revert InvalidVoteChoice();
        if (creditsToSpend == 0) revert ZeroCreditsSpent();

        ProposalVote storage pv = _proposalVotes[proposalId];
        if (pv.hasVoted[voter]) revert AlreadyVoted();

        // Verify membership at snapshot block
        uint256 balance = memberToken.getPastBalanceOf(voter, tokenId, snapshot);
        if (balance == 0) revert NotMember();

        // Verify credit budget based on snapshot CRS
        uint256 maxCredits = getCreditBudget(voter, tokenId, snapshot);
        uint256 spentInEpoch = epochSpentCredits[epochId][voter];
        if (spentInEpoch + creditsToSpend > maxCredits) {
            revert InsufficientVotingCredits();
        }

        // Deduct credits from epoch pool (bounded rationality across batched proposals)
        epochSpentCredits[epochId][voter] = spentInEpoch + creditsToSpend;

        // Calculate quadratic votes: V = sqrt(C)
        uint256 votesCast = Math.sqrt(creditsToSpend);

        pv.hasVoted[voter] = true;
        pv.spentCredits[voter] = creditsToSpend;

        if (support == 0) {
            pv.againstVotes += votesCast;
        } else if (support == 1) {
            pv.forVotes += votesCast;
        } else {
            pv.abstainVotes += votesCast;
        }

        emit EpochCreditsSpent(epochId, voter, creditsToSpend, spentInEpoch + creditsToSpend);
        emit QuadraticVoteCast(voter, proposalId, support, creditsToSpend, votesCast);
        return votesCast;
    }

    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    function getSpentCredits(uint256 proposalId, address account) external view returns (uint256) {
        return _proposalVotes[proposalId].spentCredits[account];
    }

    function getVotes(uint256 proposalId)
        external
        view
        override
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        ProposalVote storage pv = _proposalVotes[proposalId];
        return (pv.forVotes, pv.againstVotes, pv.abstainVotes);
    }

    function hasPassed(uint256 proposalId) external view override returns (bool) {
        ProposalVote storage pv = _proposalVotes[proposalId];
        return (pv.forVotes >= quadraticQuorum && pv.forVotes > pv.againstVotes);
    }

    /**
     * @notice Current timepoint synced from MemberToken with safe fallback.
     */
    function clock() public view virtual override returns (uint48) {
        if (address(memberToken).code.length > 0) {
            try memberToken.clock() returns (uint48 timepoint) {
                return timepoint;
            } catch {
                return uint48(block.number);
            }
        }
        return uint48(block.number);
    }

    /**
     * @notice Description of the clock mode synced from MemberToken with safe fallback.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        if (address(memberToken).code.length > 0) {
            try memberToken.CLOCK_MODE() returns (string memory mode) {
                return mode;
            } catch {
                return "mode=blocknumber&finality=finalized";
            }
        }
        return "mode=blocknumber&finality=finalized";
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[48] private __gap;
}
