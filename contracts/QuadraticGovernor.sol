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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "contracts/ICrsManager.sol";
import "contracts/QuadraticToken.sol";
import "contracts/IGovernor.sol";

/**
 * @title QuadraticGovernor
 * @dev This governor handles the "how" of a proposal using quadratic voting.
 * It mints transient, non-transferable ERC20 tokens for voting.
 */
abstract contract QuadraticGovernor is Initializable, GovernorUpgradeable, GovernorSettingsUpgradeable, GovernorCountingSimpleUpgradeable, GovernorTimelockControlUpgradeable, UUPSUpgradeable {
    ICrsManager public crsManager;
    IERC721 public nft;
    QVVotingToken public qvToken;

    mapping(uint256 => mapping(address => bool)) public hasMintedForProposal;

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
        __GovernorSettings_init(_proposalThreshold, _votingPeriod, 0);
        __GovernorCountingSimple_init();
        __GovernorTimelockControl_init(_timelock);
        __UUPSUpgradeable_init();
        crsManager = ICrsManager(_crsManager);
        nft = IERC721(_nft);
        qvToken = new QVVotingToken(address(this));
    }

    function castVote(uint256 proposalId, uint8 support, uint256 nftId, uint256 votes) public returns (uint256) {
        bytes memory params = abi.encode(nftId, votes);
        _castVote(proposalId, _msgSender(), support, params);
        return qvToken.balanceOf(_msgSender());
    }

    function _castVote(uint256 proposalId, address account, uint8 support, bytes memory params) internal virtual returns (uint256) {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not active");
        
        (uint256 nftId, uint256 votes) = abi.decode(params, (uint256, uint256));

        // Mint tokens for the voter if it's their first time voting on this proposal
        if (!hasMintedForProposal[proposalId][account]) {
            require(nft.ownerOf(nftId) == account, "QG: Voter does not own NFT");
            uint256 score = crsManager.getCrs(nftId);
            uint256 scaledScore = (score * 1000) / 1e18;
            uint256 tokensToMint = Math.sqrt(scaledScore);
            if (tokensToMint > 0) {
                qvToken.mint(account, tokensToMint);
            }
            hasMintedForProposal[proposalId][account] = true;
        }

        // Calculate the cost of the vote (votes^2) and burn the tokens
        uint256 cost = votes * votes;
        require(qvToken.balanceOf(account) >= cost, "QG: insufficient tokens for vote cost");
        qvToken.burn(account, cost);

        // Record the vote in the governor, using the number of "votes" as the weight
        _countVote(proposalId, account, support, votes, params);

        emit VoteCast(account, proposalId, support, votes, "");
        return votes;
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
