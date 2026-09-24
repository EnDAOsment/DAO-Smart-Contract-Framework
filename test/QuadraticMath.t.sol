// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/MemberToken.sol";
import "test/mocks/MockCrsManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract QuadraticMathTest is Test {
    QuadraticGovernor public quadraticGov;
    ERC1155TokenUpgradeable public memberToken;
    MockCrsManager public crsManager;

    address public admin = address(0xAD);
    address public voter = address(0x99);
    uint256 public constant BADGE_ID = 1;

    function setUp() public {
        address tokenImpl = address(new ERC1155TokenUpgradeable());
        bytes memory tokenInit = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (admin, admin, admin, "uri")
        );
        memberToken = ERC1155TokenUpgradeable(address(new ERC1967Proxy(tokenImpl, tokenInit)));

        crsManager = new MockCrsManager();

        address qImpl = address(new QuadraticGovernor());
        bytes memory qInit = abi.encodeCall(
            QuadraticGovernor.initialize,
            (address(this), address(memberToken), address(crsManager), 10)
        );
        quadraticGov = QuadraticGovernor(address(new ERC1967Proxy(qImpl, qInit)));

        vm.prank(admin);
        memberToken.mint(voter, BADGE_ID, 1, "");
    }

    function test_QuadraticMath_SquareRootProperty(uint256 credits) public pure {
        vm.assume(credits > 0 && credits < 1e36);
        uint256 votes = Math.sqrt(credits);

        // V^2 <= C < (V+1)^2
        assertTrue(votes * votes <= credits);
        if (votes < type(uint128).max) {
            assertTrue((votes + 1) * (votes + 1) > credits);
        }
    }

    function test_QuadraticMath_Monotonicity(uint256 c1, uint256 c2) public pure {
        vm.assume(c1 > 0 && c1 < 1e36);
        vm.assume(c2 > 0 && c2 < 1e36);

        uint256 v1 = Math.sqrt(c1);
        uint256 v2 = Math.sqrt(c2);

        if (c1 <= c2) {
            assertTrue(v1 <= v2);
        } else {
            assertTrue(v1 >= v2);
        }
    }

    function test_CreditBudget_Scaling(uint256 score) public {
        vm.assume(score <= 1e28); // Up to 10 billion CRS
        crsManager.setCrs(voter, BADGE_ID, score);

        uint256 budget = quadraticGov.getCreditBudget(voter, BADGE_ID);
        assertTrue(budget >= quadraticGov.MIN_CREDITS());
        if (score / quadraticGov.CREDITS_SCALE() > quadraticGov.MIN_CREDITS()) {
            assertEq(budget, score / quadraticGov.CREDITS_SCALE());
        }
    }
}
