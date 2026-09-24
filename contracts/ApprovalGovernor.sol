// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./MemberToken.sol";
import "./ICrsManager.sol";
import "./IStageGovernor.sol";

/**
 * @title ApprovalGovernor
 * @dev Governance module for Stage 1: Proposal (Value) Ranking (Approval Voting).
 * Votes are weighted by the voter's Contribution Reputation Score (CRS) snapshot.
 */
contract ApprovalGovernor is Initializable, OwnableUpgradeable, UUPSUpgradeable, IStageGovernor {
    struct ProposalVote {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    ERC1155TokenUpgradeable public memberToken;
    ICrsManager public crsManager;
    address public governorGeneral;
    uint256 public quorumScore;

    mapping(uint256 => ProposalVote) private _proposalVotes;

    event ApprovalVoteCast(address indexed voter, uint256 indexed proposalId, uint8 support, uint256 weight);
    event QuorumScoreUpdated(uint256 oldQuorumScore, uint256 newQuorumScore);
    event GovernorGeneralUpdated(address indexed oldGovernorGeneral, address indexed newGovernorGeneral);

    error OnlyGovernorGeneral();
    error AlreadyVoted();
    error NotMember();
    error InvalidVoteChoice();
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
        uint256 _quorumScore
    ) public initializer {
        if (_owner == address(0) || _memberToken == address(0) || _crsManager == address(0)) {
            revert ZeroAddress();
        }
        __Ownable_init(_owner);

        memberToken = ERC1155TokenUpgradeable(_memberToken);
        crsManager = ICrsManager(_crsManager);
        quorumScore = _quorumScore;
    }

    function setGovernorGeneral(address _governorGeneral) external onlyOwner {
        if (_governorGeneral == address(0)) revert ZeroAddress();
        address old = governorGeneral;
        governorGeneral = _governorGeneral;
        emit GovernorGeneralUpdated(old, _governorGeneral);
    }

    function setQuorumScore(uint256 _quorumScore) external onlyOwner {
        uint256 old = quorumScore;
        quorumScore = _quorumScore;
        emit QuorumScoreUpdated(old, _quorumScore);
    }

    /**
     * @notice Returns stage identifier (1 = Approval).
     */
    function stageId() external pure override returns (uint8) {
        return 1;
    }

    /**
     * @notice Casts an approval vote for a proposal.
     * @param proposalId The ID of the proposal.
     * @param voter The address of the voter.
     * @param support 0 = Against, 1 = For, 2 = Abstain.
     * @param tokenId The ERC1155 member badge token ID.
     * @param snapshot The snapshot block number for balance check.
     */
    function castVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        uint256 tokenId,
        uint256 snapshot
    ) external onlyGovernorGeneral returns (uint256) {
        if (support > 2) revert InvalidVoteChoice();

        ProposalVote storage pv = _proposalVotes[proposalId];
        if (pv.hasVoted[voter]) revert AlreadyVoted();

        // Verify membership at snapshot block
        uint256 balance = memberToken.getPastBalanceOf(voter, tokenId, snapshot);
        if (balance == 0) revert NotMember();

        // Calculate vote weight based on snapshot CRS (immune to post-proposal score change)
        uint256 score = crsManager.getPastCrs(voter, tokenId, snapshot);
        // Default base weight of 1e18 if score is 0
        uint256 weight = score > 0 ? score : 1e18;

        pv.hasVoted[voter] = true;

        if (support == 0) {
            pv.againstVotes += weight;
        } else if (support == 1) {
            pv.forVotes += weight;
        } else {
            pv.abstainVotes += weight;
        }

        emit ApprovalVoteCast(voter, proposalId, support, weight);
        return weight;
    }

    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
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
        return (pv.forVotes >= quorumScore && pv.forVotes > pv.againstVotes);
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

    uint256[49] private __gap;
}
