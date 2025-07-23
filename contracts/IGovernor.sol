// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

/**
 * @title IGovernor
 * @dev Interface to interact with Governor contracts, used by GovernorGeneral.
 * This resolves the "Undeclared identifier" error.
 */
interface IGovernor {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId);

    function state(uint256 proposalId) external view returns (ProposalState);
}