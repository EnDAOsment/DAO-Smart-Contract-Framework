// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IStageGovernor
 * @notice Standardized interface for modular governance stages in the GovernorGeneral framework.
 */
interface IStageGovernor {
    /**
     * @notice Returns the unique stage identifier (e.g., 1 for Approval, 2 for Quadratic).
     */
    function stageId() external view returns (uint8);

    /**
     * @notice Determines whether a proposal has met the criteria to pass this stage.
     * @param proposalId The ID of the proposal.
     */
    function hasPassed(uint256 proposalId) external view returns (bool);

    /**
     * @notice Returns current vote tallies for a proposal.
     * @param proposalId The ID of the proposal.
     * @return forVotes Number of affirmative votes / weight.
     * @return againstVotes Number of negative votes / weight.
     * @return abstainVotes Number of abstentions.
     */
    function getVotes(uint256 proposalId)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);

    /**
     * @notice Current timepoint as block number or timestamp.
     */
    function clock() external view returns (uint48);

    /**
     * @notice Description of the clock mode.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external view returns (string memory);
}
