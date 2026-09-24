// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract MockTarget {
    uint256 public value;
    event TargetExecuted(uint256 newValue);

    function setValue(uint256 newValue) external payable {
        value = newValue;
        emit TargetExecuted(newValue);
    }
}
