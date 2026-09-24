// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

/**
 * @title ICrsManager
 * @dev Interface for the Contribution Reputation Score Manager contract.
 * Provides the CRS for a given user account and member token ID.
 */
interface ICrsManager {
    function getCrs(address account, uint256 tokenId) external view returns (uint256);
    function getPastCrs(address account, uint256 tokenId, uint256 timepoint) external view returns (uint256);
}
