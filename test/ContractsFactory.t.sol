// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "contracts/ContractsFactory.sol";
import "contracts/MemberToken.sol";
import "contracts/ApprovalGovernor.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/GovernorGeneral.sol";
import "test/mocks/MockCrsManager.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ContractsFactoryTest is Test {
    ContractsFactory public factory;
    MockCrsManager public crsManager;

    address public factoryOwner = address(0xF00);
    address public agency1Admin = address(0xA1);
    address public agency2Admin = address(0xA2);

    function setUp() public {
        vm.roll(500);

        crsManager = new MockCrsManager();

        address memberTokenImpl = address(new ERC1155TokenUpgradeable());
        address timelockImpl = address(new TimelockControllerUpgradeable());
        address approvalGovImpl = address(new ApprovalGovernor());
        address quadraticGovImpl = address(new QuadraticGovernor());
        address governorGeneralImpl = address(new GovernorGeneral());

        address factoryImpl = address(new ContractsFactory());
        bytes memory initData = abi.encodeCall(
            ContractsFactory.initialize,
            (factoryOwner, memberTokenImpl, timelockImpl, approvalGovImpl, quadraticGovImpl, governorGeneralImpl)
        );
        factory = ContractsFactory(address(new ERC1967Proxy(factoryImpl, initData)));
    }

    function test_Factory_Initialize() public view {
        assertEq(factory.owner(), factoryOwner);
        assertTrue(factory.memberTokenImpl() != address(0));
        assertTrue(factory.timelockImpl() != address(0));
        assertTrue(factory.approvalGovImpl() != address(0));
        assertTrue(factory.quadraticGovImpl() != address(0));
        assertTrue(factory.governorGeneralImpl() != address(0));
    }

    function test_Factory_DeployAgencyDAO_Success() public {
        ContractsFactory.AgencyDAOConfig memory config = ContractsFactory.AgencyDAOConfig({
            agencyAdmin: agency1Admin,
            tokenUri: "https://agency1.org/badges/{id}.json",
            crsManager: address(crsManager),
            approvalQuorum: 50e18,
            quadraticQuorum: 100,
            timelockMinDelay: 2 days,
            votingDelay: 2,
            approvalPeriod: 100,
            quadraticPeriod: 100,
            proposalThreshold: 1,
            defaultMemberTokenId: 1
        });

        ContractsFactory.AgencyDAODeployment memory d = factory.deployAgencyDAO(config);

        assertTrue(d.memberToken != address(0));
        assertTrue(d.timelock != address(0));
        assertTrue(d.approvalGovernor != address(0));
        assertTrue(d.quadraticGovernor != address(0));
        assertTrue(d.governorGeneral != address(0));

        // Check MemberToken roles
        ERC1155TokenUpgradeable token = ERC1155TokenUpgradeable(d.memberToken);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), agency1Admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), agency1Admin));
        assertFalse(token.hasRole(token.MINTER_ROLE(), address(factory)));

        // Check Timelock roles
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(d.timelock));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), d.governorGeneral));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), agency1Admin));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(factory)));

        // Check Governor owners
        assertEq(GovernorGeneral(d.governorGeneral).owner(), agency1Admin);
        assertEq(ApprovalGovernor(d.approvalGovernor).owner(), agency1Admin);
        assertEq(QuadraticGovernor(d.quadraticGovernor).owner(), agency1Admin);

        assertEq(factory.totalDeployments(), 1);
    }

    function test_Factory_DeployMultipleAgencies() public {
        ContractsFactory.AgencyDAOConfig memory config1 = ContractsFactory.AgencyDAOConfig({
            agencyAdmin: agency1Admin,
            tokenUri: "https://agency1.org/badges/{id}.json",
            crsManager: address(crsManager),
            approvalQuorum: 50e18,
            quadraticQuorum: 100,
            timelockMinDelay: 2 days,
            votingDelay: 2,
            approvalPeriod: 100,
            quadraticPeriod: 100,
            proposalThreshold: 1,
            defaultMemberTokenId: 1
        });

        ContractsFactory.AgencyDAOConfig memory config2 = ContractsFactory.AgencyDAOConfig({
            agencyAdmin: agency2Admin,
            tokenUri: "https://agency2.org/badges/{id}.json",
            crsManager: address(crsManager),
            approvalQuorum: 20e18,
            quadraticQuorum: 50,
            timelockMinDelay: 1 days,
            votingDelay: 1,
            approvalPeriod: 50,
            quadraticPeriod: 50,
            proposalThreshold: 5,
            defaultMemberTokenId: 2
        });

        ContractsFactory.AgencyDAODeployment memory d1 = factory.deployAgencyDAO(config1);
        ContractsFactory.AgencyDAODeployment memory d2 = factory.deployAgencyDAO(config2);

        assertTrue(d1.governorGeneral != d2.governorGeneral);
        assertTrue(d1.memberToken != d2.memberToken);
        assertTrue(d1.timelock != d2.timelock);

        assertEq(factory.totalDeployments(), 2);
    }
}
