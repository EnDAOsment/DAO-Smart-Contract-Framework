// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title QVVotingToken
 * @dev A transient, burnable ERC20 token for quadratic voting.
 * These tokens are non-transferable and are minted by the QuadraticGovernor
 * at the start of a voting period and burned at the end.
 */
contract QVVotingToken is ERC20, ERC20Permit, ERC20Votes {
    // The purpose of this contract is create a transient burnable voting token for eligible votes at the time of the tally
    // The number of tokens minted per user is based on the round down number of sqrt of the voter's contribution reputable score

    address public governor;

    constructor(address _governor) ERC20("Quadratic Voting Token", "QVT") ERC20Permit("Quadratic Voting Token") {
        governor = _governor;
    }

    // The functions below are overrides required by Solidity.

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    // Gemini
    function mint(address to, uint256 amount) public {
        require(msg.sender == governor, "QVT: Only governor can mint");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(msg.sender == governor, "QVT: Only governor can burn");
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 amount) internal virtual override(ERC20, ERC20Votes) {
        // This hook is called by _transfer, _mint, and _burn.
        // We want to allow minting (from address(0)) and burning (to address(0)),
        // but prevent regular transfers (from != address(0) and to != address(0)).
        if (from != address(0) && to != address(0)) {
            revert("QVT: Non-transferable");
        }
        super._update(from, to, amount);
    }
}
