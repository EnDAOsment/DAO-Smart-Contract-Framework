// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "contracts/MemberToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MemberTokenTest is Test {
    ERC1155TokenUpgradeable public memberToken;
    address public admin = address(0xAD);
    address public minter = address(0xB0B);
    address public alice = address(0xAA);
    address public bob = address(0xBB);

    function setUp() public {
        address impl = address(new ERC1155TokenUpgradeable());
        bytes memory initData = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (admin, minter, admin, "https://api.daoframework.io/token/{id}.json")
        );
        address proxy = address(new ERC1967Proxy(impl, initData));
        memberToken = ERC1155TokenUpgradeable(proxy);
    }

    function test_MemberToken_Initialize() public view {
        assertTrue(memberToken.hasRole(memberToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(memberToken.hasRole(memberToken.MINTER_ROLE(), minter));
        assertEq(memberToken.uri(1), "https://api.daoframework.io/token/{id}.json");
    }

    function test_MemberToken_Mint() public {
        vm.prank(minter);
        memberToken.mint(alice, 1, 100, "");

        assertEq(memberToken.balanceOf(alice, 1), 100);
    }

    function test_MemberToken_RevertSoulboundTransfer() public {
        vm.prank(minter);
        memberToken.mint(alice, 1, 100, "");

        // Alice attempts to transfer to Bob
        vm.prank(alice);
        vm.expectRevert(ERC1155TokenUpgradeable.SoulboundTokenTransferDisabled.selector);
        memberToken.safeTransferFrom(alice, bob, 1, 50, "");
    }

    function test_MemberToken_Checkpoints() public {
        vm.roll(5);
        vm.prank(minter);
        memberToken.mint(alice, 1, 100, "");

        vm.roll(15);
        assertEq(memberToken.getPastBalanceOf(alice, 1, 5), 100);

        vm.prank(minter);
        memberToken.mint(alice, 1, 50, "");

        vm.roll(25);
        assertEq(memberToken.getPastBalanceOf(alice, 1, 5), 100);
        assertEq(memberToken.getPastBalanceOf(alice, 1, 15), 150);
    }

    function test_MemberToken_Burn() public {
        vm.prank(minter);
        memberToken.mint(alice, 1, 100, "");

        vm.prank(alice);
        memberToken.burn(alice, 1, 40);

        assertEq(memberToken.balanceOf(alice, 1), 60);
    }
}
