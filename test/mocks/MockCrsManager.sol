// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "contracts/ICrsManager.sol";

contract MockCrsManager is ICrsManager {
    mapping(address => mapping(uint256 => uint256)) private _scores;

    function setCrs(address account, uint256 tokenId, uint256 score) external {
        _scores[account][tokenId] = score;
    }

    function getCrs(address account, uint256 tokenId) external view override returns (uint256) {
        return _scores[account][tokenId];
    }

    function getPastCrs(address account, uint256 tokenId, uint256) external view override returns (uint256) {
        return _scores[account][tokenId];
    }
}
