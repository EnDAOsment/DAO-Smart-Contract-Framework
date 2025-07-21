// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {HybridBeaconUUPSFactory} from "src/HybridBeaconUUPSFactory.sol";

contract HybridBeaconUUPSFactoryTest is Test {
  HybridBeaconUUPSFactory public instance;

  function setUp() public {
    address initialOwner = vm.addr(1);
    address proxy = Upgrades.deployUUPSProxy(
      "HybridBeaconUUPSFactory.sol",
      abi.encodeCall(HybridBeaconUUPSFactory.initialize, (initialOwner))
    );
    instance = HybridBeaconUUPSFactory(proxy);
  }

  function testSomething() public {
    // Add your test here
  }
}
