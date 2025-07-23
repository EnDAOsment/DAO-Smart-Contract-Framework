// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {GovernorVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./ICrsManager.sol";

/**
 * @title ApprovalGovernor
 * @dev This governor handles the initial "why" of a proposal.
 * It uses a simple approval voting system where the sum of Contribution
 * Reputation Scores of "For" votes must exceed a threshold.
 */
abstract contract ApprovalGovernor is Initializable, GovernorUpgradeable, GovernorSettingsUpgradeable, GovernorCountingSimpleUpgradeable, GovernorTimelockControlUpgradeable, UUPSUpgradeable {
    ICrsManager public crsManager;
    IERC721 public nft;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        address _crsManager,
        address _nft,
        TimelockControllerUpgradeable _timelock,
        uint32 _votingPeriod,
        uint48 _proposalThreshold
    ) public initializer {
        __Governor_init(_name);
        __GovernorSettings_init(_proposalThreshold, _votingPeriod, 0); // initial delay is 0
        __GovernorCountingSimple_init();
        __GovernorTimelockControl_init(_timelock);
        __UUPSUpgradeable_init();
        crsManager = ICrsManager(_crsManager);
        nft = IERC721(_nft);
    }

    /**
     * @notice Allows a user to cast a vote using a specific NFT as their voting power.
     * @param proposalId The ID of the proposal to vote on.
     * @param support The choice for the vote (For, Against, Abstain).
     * @param nftId The ID of the NFT to use for calculating voting power.
     * @return The weight of the vote cast.
     */
    function castVoteWithNft(uint256 proposalId, uint8 support, uint256 nftId) public returns (uint256) {
        require(msg.sender == _msgSender(), "Only the intended voter should vote.");
        return _castVote(proposalId, _msgSender(), support, abi.encode(nftId));
    }

    function _castVote(uint256 proposalId, address account, uint8 support, bytes memory params) internal virtual returns (uint256) {
        // Get the voting weight based on the user's reputation score and the specific NFT.
        // This is where your custom logic for reputation-based voting power comes in.
        // uint256 weight = crsManager.getContributionReputationScore(account, nftId);
        uint256 weight = _getVoteWeight(account, params); // Placeholder until crsManager.getContributionReputationScore is developed 
        require(weight > 0, "ApprovalGovernor: Voter has no reputation score or NFT is not valid for voting");

        // Use the internal _countVote provided by GovernorCountingSimpleUpgradeable
        // ADDED THE FIFTH ARGUMENT: abi.encode() for empty bytes
        // _countVote(proposalId, account, support, weight, abi.encode());
        _countVote(proposalId, account, support, weight, params);

        // Emit the standard VoteCast event
        emit VoteCast(account, proposalId, support, weight, ""); // reason is empty string as we use nftId
        return weight;
    }

    function _getVoteWeight(address account, bytes memory params) internal view returns (uint256) {
        uint256 nftId = abi.decode(params, (uint256));
        require(nft.ownerOf(nftId) == account, "AG: Voter does not own NFT");

        uint256 score = crsManager.getCrs(nftId);
        // The score is scaled by 1000 to handle decimals, as it's between 0.5 and 2.
        uint256 weight = (score * 1000) / 1e18;
        return weight;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}
    
    // The following functions are overrides required by Solidity.
    function state(uint256 proposalId) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (ProposalState) { return super.state(proposalId); }
    function proposalNeedsQueuing(uint256 proposalId) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (bool) { return super.proposalNeedsQueuing(proposalId); }
    function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) { return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash); }
    function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) { super._executeOperations(proposalId, targets, values, calldatas, descriptionHash); }
    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) { return super._cancel(targets, values, calldatas, descriptionHash); }
    function _executor() internal view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (address) { return super._executor(); }
    
    function proposalThreshold() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.proposalThreshold();
    }
}
