// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "contracts/ContractsFactory.sol";
import "contracts/MemberToken.sol";
import "contracts/ApprovalGovernor.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/GovernorGeneral.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy base implementations
        address memberTokenImpl = address(new ERC1155TokenUpgradeable());
        address timelockImpl = address(new TimelockControllerUpgradeable());
        address approvalGovImpl = address(new ApprovalGovernor());
        address quadraticGovImpl = address(new QuadraticGovernor());
        address governorGeneralImpl = address(new GovernorGeneral());

        // 2. Deploy Factory
        address factoryImpl = address(new ContractsFactory());
        bytes memory initData = abi.encodeCall(
            ContractsFactory.initialize,
            (deployer, memberTokenImpl, timelockImpl, approvalGovImpl, quadraticGovImpl, governorGeneralImpl)
        );
        address factoryProxy = address(new ERC1967Proxy(factoryImpl, initData));

        console.log("ContractsFactory Proxy deployed at:", factoryProxy);

        vm.stopBroadcast();
    }
}
