// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "contracts/MemberToken.sol";
import "contracts/ApprovalGovernor.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/GovernorGeneral.sol";
import "contracts/ContractsFactory.sol";
import "test/mocks/MockCrsManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

// Mock V2 implementations for testing upgrades
contract MemberTokenV2 is ERC1155TokenUpgradeable {
    function version() external pure returns (string memory) {
        return "v2.0";
    }
}

contract ApprovalGovernorV2 is ApprovalGovernor {
    function version() external pure returns (string memory) {
        return "v2.0";
    }
}

contract QuadraticGovernorV2 is QuadraticGovernor {
    function version() external pure returns (string memory) {
        return "v2.0";
    }
}

contract GovernorGeneralV2 is GovernorGeneral {
    function version() external pure returns (string memory) {
        return "v2.0";
    }
}

contract ContractsFactoryV2 is ContractsFactory {
    function version() external pure returns (string memory) {
        return "v2.0";
    }
}

contract UpgradeabilityTest is Test {
    address public owner = address(0xAA1);
    address public nonOwner = address(0xBAD);

    function test_MemberToken_Upgrade() public {
        address impl1 = address(new ERC1155TokenUpgradeable());
        bytes memory init = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (owner, owner, owner, "uri")
        );
        address proxy = address(new ERC1967Proxy(impl1, init));

        ERC1155TokenUpgradeable token = ERC1155TokenUpgradeable(proxy);
        vm.prank(owner);
        token.mint(owner, 1, 50, "");
        assertEq(token.balanceOf(owner, 1), 50);

        address impl2 = address(new MemberTokenV2());

        // Non-upgrader reverts
        vm.prank(nonOwner);
        vm.expectRevert();
        token.upgradeToAndCall(impl2, "");

        // Authorized upgrader succeeds
        vm.prank(owner);
        token.upgradeToAndCall(impl2, "");

        assertEq(MemberTokenV2(proxy).version(), "v2.0");
        assertEq(MemberTokenV2(proxy).balanceOf(owner, 1), 50); // State preserved
    }

    function test_ApprovalGovernor_Upgrade() public {
        address token = address(0x123);
        address crs = address(0x456);
        address impl1 = address(new ApprovalGovernor());
        bytes memory init = abi.encodeCall(
            ApprovalGovernor.initialize,
            (owner, token, crs, 100)
        );
        address proxy = address(new ERC1967Proxy(impl1, init));

        ApprovalGovernor gov = ApprovalGovernor(proxy);
        assertEq(gov.quorumScore(), 100);

        address impl2 = address(new ApprovalGovernorV2());

        // Non-owner reverts
        vm.prank(nonOwner);
        vm.expectRevert();
        gov.upgradeToAndCall(impl2, "");

        // Owner succeeds
        vm.prank(owner);
        gov.upgradeToAndCall(impl2, "");

        assertEq(ApprovalGovernorV2(proxy).version(), "v2.0");
        assertEq(ApprovalGovernorV2(proxy).quorumScore(), 100);
    }

    function test_QuadraticGovernor_Upgrade() public {
        address token = address(0x123);
        address crs = address(0x456);
        address impl1 = address(new QuadraticGovernor());
        bytes memory init = abi.encodeCall(
            QuadraticGovernor.initialize,
            (owner, token, crs, 200)
        );
        address proxy = address(new ERC1967Proxy(impl1, init));

        QuadraticGovernor gov = QuadraticGovernor(proxy);
        assertEq(gov.quadraticQuorum(), 200);

        address impl2 = address(new QuadraticGovernorV2());

        // Non-owner reverts
        vm.prank(nonOwner);
        vm.expectRevert();
        gov.upgradeToAndCall(impl2, "");

        // Owner succeeds
        vm.prank(owner);
        gov.upgradeToAndCall(impl2, "");

        assertEq(QuadraticGovernorV2(proxy).version(), "v2.0");
        assertEq(QuadraticGovernorV2(proxy).quadraticQuorum(), 200);
    }

    function test_GovernorGeneral_Upgrade() public {
        address token = address(0x123);
        address appGov = address(0x456);
        address quadGov = address(0x789);
        address timelock = address(0xABC);

        address impl1 = address(new GovernorGeneral());
        bytes memory init = abi.encodeCall(
            GovernorGeneral.initialize,
            (token, appGov, quadGov, payable(timelock), 1, 10, 10, 1, 1)
        );
        address proxy = address(new ERC1967Proxy(impl1, init));

        GovernorGeneral gen = GovernorGeneral(proxy);
        assertEq(gen.votingDelay(), 1);

        address impl2 = address(new GovernorGeneralV2());

        // Non-owner reverts
        vm.prank(nonOwner);
        vm.expectRevert();
        gen.upgradeToAndCall(impl2, "");

        // Owner succeeds
        vm.prank(address(this));
        gen.upgradeToAndCall(impl2, "");

        assertEq(GovernorGeneralV2(proxy).version(), "v2.0");
        assertEq(GovernorGeneralV2(proxy).votingDelay(), 1);
    }

    function test_ContractsFactory_Upgrade() public {
        address impl1 = address(new ContractsFactory());
        bytes memory init = abi.encodeCall(
            ContractsFactory.initialize,
            (owner, address(0x1), address(0x2), address(0x3), address(0x4), address(0x5))
        );
        address proxy = address(new ERC1967Proxy(impl1, init));

        ContractsFactory factory = ContractsFactory(proxy);
        assertEq(factory.owner(), owner);

        address impl2 = address(new ContractsFactoryV2());

        // Non-owner reverts
        vm.prank(nonOwner);
        vm.expectRevert();
        factory.upgradeToAndCall(impl2, "");

        // Owner succeeds
        vm.prank(owner);
        factory.upgradeToAndCall(impl2, "");

        assertEq(ContractsFactoryV2(proxy).version(), "v2.0");
        assertEq(ContractsFactoryV2(proxy).owner(), owner);
    }
}
