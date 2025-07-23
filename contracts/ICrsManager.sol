// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

/**
 * @title ICrsManager
 * @dev Interface for the Contribution Reputation Score Manager contract.
 * This contract is responsible for decrypting and providing the CRS for a given user.
 */
interface ICrsManager {
    function getCrs(uint256 nftId) external view returns (uint256);
}
