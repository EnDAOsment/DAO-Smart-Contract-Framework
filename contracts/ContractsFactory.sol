// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./MemberToken.sol";

contract HybridBeaconUUPSFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
   Tokenizer[] public MemberTokenArray;

   function CreateNewTokenizer(string memory _tokenizing) public {
     Tokenizer tokenizer = new Tokenizer(_tokenizing);
     MemberTokenArray.push(tokenizer);
   }

   function gfSetter(uint256 _tokenizerIndex, string memory _tokenizing) public {
     Tokenizer(address(MemberTokenArray[_tokenizerIndex])).setTokenizing(_tokenizing);
   }

   function gfGetter(uint256 _tokenizerIndex) public view returns (string memory) {
    return Tokenizer(address(MemberTokenArray[_tokenizerIndex])).tokenize();
   }    
}
