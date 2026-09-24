// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "contracts/MemberToken.sol";
import "contracts/ApprovalGovernor.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/GovernorGeneral.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployDirectDAO is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. MemberToken
        address tokenImpl = address(new ERC1155TokenUpgradeable());
        bytes memory tokenInit = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (deployer, deployer, deployer, "https://api.daoframework.io/token/{id}.json")
        );
        address memberToken = address(new ERC1967Proxy(tokenImpl, tokenInit));

        // 2. Timelock
        address timelockImpl = address(new TimelockControllerUpgradeable());
        address[] memory empty = new address[](0);
        bytes memory timelockInit = abi.encodeCall(
            TimelockControllerUpgradeable.initialize,
            (2 days, empty, empty, deployer)
        );
        address payable timelock = payable(address(new ERC1967Proxy(timelockImpl, timelockInit)));

        // 3. ApprovalGovernor
        address crsManager = vm.envOr("CRS_MANAGER", deployer);
        address approvalImpl = address(new ApprovalGovernor());
        bytes memory approvalInit = abi.encodeCall(
            ApprovalGovernor.initialize,
            (deployer, memberToken, crsManager, 10e18)
        );
        address approvalGov = address(new ERC1967Proxy(approvalImpl, approvalInit));

        // 4. QuadraticGovernor
        address quadraticImpl = address(new QuadraticGovernor());
        bytes memory quadraticInit = abi.encodeCall(
            QuadraticGovernor.initialize,
            (deployer, memberToken, crsManager, 20)
        );
        address quadraticGov = address(new ERC1967Proxy(quadraticImpl, quadraticInit));

        // 5. GovernorGeneral
        address generalImpl = address(new GovernorGeneral());
        bytes memory generalInit = abi.encodeCall(
            GovernorGeneral.initialize,
            (
                memberToken,
                approvalGov,
                quadraticGov,
                timelock,
                1,      // votingDelay (blocks)
                50400,  // approvalPeriod (~1 week)
                50400,  // quadraticPeriod (~1 week)
                1,      // proposalThreshold
                1       // defaultMemberTokenId
            )
        );
        address governorGeneral = address(new ERC1967Proxy(generalImpl, generalInit));

        // Connect GovernorGeneral
        ApprovalGovernor(approvalGov).setGovernorGeneral(governorGeneral);
        QuadraticGovernor(quadraticGov).setGovernorGeneral(governorGeneral);

        // Configure Timelock
        TimelockControllerUpgradeable tl = TimelockControllerUpgradeable(timelock);
        tl.grantRole(tl.PROPOSER_ROLE(), governorGeneral);
        tl.grantRole(tl.CANCELLER_ROLE(), governorGeneral);
        tl.grantRole(tl.EXECUTOR_ROLE(), address(0));

        vm.stopBroadcast();
    }
}
