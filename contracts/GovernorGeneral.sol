// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "contracts/ICrsManager.sol";
import "contracts/IGovernor.sol";

/**
 * @title GovernorGeneral
 * @dev The core contract of the DAO, serving as the main entry point for proposals.
 * It determines which Governor (Approval or Quadratic) to use for a proposal.
 * This contract is upgradeable.
 */
contract GovernorGeneral is Initializable, UUPSUpgradeable {
    enum ProposalStage { Approval, Quadratic }

    struct Proposal {
        address proposer;
        ProposalStage stage;
        address governor;
        bool exists;
    }

    mapping(uint256 => Proposal) public proposals;
    address public approvalGovernor;
    address public quadraticGovernor;
    address public crsManager;
    address public owner;

    event ProposalCreated(uint256 proposalId, address proposer, ProposalStage stage, address governor);
    event ProposalStageChanged(uint256 proposalId, ProposalStage newStage, address newGovernor);

    modifier onlyOwner() {
        require(msg.sender == owner, "GG: Not the owner");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _approvalGovernor, address _quadraticGovernor, address _crsManager) public initializer {
        __UUPSUpgradeable_init();
        approvalGovernor = _approvalGovernor;
        quadraticGovernor = _quadraticGovernor;
        crsManager = _crsManager;
        owner = msg.sender;
    }

    function createProposal(string memory description, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) public returns (uint256) {
        // Initially, all proposals start at the Approval stage.
        address governor = approvalGovernor;
        uint256 proposalId = IGovernor(governor).propose(targets, values, calldatas, description);

        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            stage: ProposalStage.Approval,
            governor: governor,
            exists: true
        });

        emit ProposalCreated(proposalId, msg.sender, ProposalStage.Approval, governor);
        return proposalId;
    }

    function advanceProposal(uint256 proposalId) public onlyOwner {
        require(proposals[proposalId].exists, "GG: Proposal does not exist");
        require(proposals[proposalId].stage == ProposalStage.Approval, "GG: Not in approval stage");
        require(IGovernor(proposals[proposalId].governor).state(proposalId) == IGovernor.ProposalState.Succeeded, "GG: Approval not passed");

        proposals[proposalId].stage = ProposalStage.Quadratic;
        proposals[proposalId].governor = quadraticGovernor;

        emit ProposalStageChanged(proposalId, ProposalStage.Quadratic, quadraticGovernor);
    }

    function getContributionReputationScore(uint256 nftId) public view returns (uint256) {
        return ICrsManager(crsManager).getCrs(nftId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

