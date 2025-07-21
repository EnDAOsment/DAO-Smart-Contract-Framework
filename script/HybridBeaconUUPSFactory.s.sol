// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {HybridBeaconUUPSFactory} from "src/HybridBeaconUUPSFactory.sol";

contract HybridBeaconUUPSFactoryScript is Script {
  function setUp() public {}

  function run() public {
    // TODO: Set addresses for the variables below, then uncomment the following section:
    /*
    vm.startBroadcast();
    address initialOwner = <Set initialOwner address here>;
    address proxy = Upgrades.deployUUPSProxy(
      "HybridBeaconUUPSFactory.sol",
      abi.encodeCall(HybridBeaconUUPSFactory.initialize, (initialOwner))
    );
    HybridBeaconUUPSFactory instance = HybridBeaconUUPSFactory(proxy);
    console.log("Proxy deployed to %s", address(instance));
    vm.stopBroadcast();
    */
  }
}
