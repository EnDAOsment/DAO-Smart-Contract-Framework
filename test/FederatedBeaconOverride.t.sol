// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "contracts/ContractsFactory.sol";
import "contracts/MemberToken.sol";
import "contracts/ApprovalGovernor.sol";
import "contracts/QuadraticGovernor.sol";
import "contracts/GovernorGeneral.sol";
import "contracts/FederatedBeaconProxy.sol";
import "contracts/IStageGovernor.sol";
import "./mocks/MockCrsManager.sol";

contract MockCustomStageGovernor is IStageGovernor {
    string public customRule;

    constructor(string memory _rule) {
        customRule = _rule;
    }

    function stageId() external pure override returns (uint8) {
        return 99; // Custom stage ID for sovereign agency
    }

    function hasPassed(uint256) external pure override returns (bool) {
        return true;
    }

    function getVotes(uint256) external pure override returns (uint256, uint256, uint256) {
        return (8888, 0, 0);
    }

    function clock() external view override returns (uint48) {
        return uint48(block.number);
    }

    function CLOCK_MODE() external pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function customAgencyFeature() external pure returns (string memory) {
        return "SovereignAgencyV1";
    }
}

contract ApprovalGovernorV3 is ApprovalGovernor {
    function federalFeatureV3() external pure returns (string memory) {
        return "FederalV3Active";
    }
}

contract FederatedBeaconOverrideTest is Test {
    ContractsFactory public factory;
    MockCrsManager public crsManager;

    address public federalProtocolOwner = address(0xFED);
    address public agencyAdmin = address(0xAA);
    address public attacker = address(0xBAD);

    address public memberTokenImpl;
    address public timelockImpl;
    address public approvalGovImpl;
    address public quadraticGovImpl;
    address public governorGeneralImpl;

    function setUp() public {
        vm.startPrank(federalProtocolOwner);

        // 1. Deploy base implementations
        memberTokenImpl = address(new ERC1155TokenUpgradeable());
        timelockImpl = address(new TimelockControllerUpgradeable());
        approvalGovImpl = address(new ApprovalGovernor());
        quadraticGovImpl = address(new QuadraticGovernor());
        governorGeneralImpl = address(new GovernorGeneral());

        // 2. Deploy Factory via UUPS proxy
        ContractsFactory factoryImpl = new ContractsFactory();
        bytes memory factoryInit = abi.encodeCall(
            ContractsFactory.initialize,
            (
                federalProtocolOwner,
                memberTokenImpl,
                timelockImpl,
                approvalGovImpl,
                quadraticGovImpl,
                governorGeneralImpl
            )
        );
        factory = ContractsFactory(address(new ERC1967Proxy(address(factoryImpl), factoryInit)));

        // 3. Create Canonical Federal Beacons
        factory.createFederalBeacons(federalProtocolOwner);

        crsManager = new MockCrsManager();

        vm.stopPrank();
    }

    function _defaultAgencyConfig() internal view returns (ContractsFactory.AgencyDAOConfig memory) {
        return ContractsFactory.AgencyDAOConfig({
            agencyAdmin: agencyAdmin,
            tokenUri: "https://federated.dao/agency/{id}.json",
            crsManager: address(crsManager),
            approvalQuorum: 200,
            quadraticQuorum: 400,
            timelockMinDelay: 2 days,
            votingDelay: 1,
            approvalPeriod: 50,
            quadraticPeriod: 50,
            proposalThreshold: 1,
            defaultMemberTokenId: 1
        });
    }

    function test_Factory_FederalBeaconsCreated() public view {
        assertNotEq(factory.memberTokenBeacon(), address(0));
        assertNotEq(factory.approvalGovBeacon(), address(0));
        assertNotEq(factory.quadraticGovBeacon(), address(0));
        assertNotEq(factory.governorGeneralBeacon(), address(0));

        assertEq(UpgradeableBeacon(factory.approvalGovBeacon()).owner(), federalProtocolOwner);
        assertEq(UpgradeableBeacon(factory.approvalGovBeacon()).implementation(), approvalGovImpl);
    }

    function test_Factory_DeployFederatedAgencyDAO_Success() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();

        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        assertNotEq(deployment.memberToken, address(0));
        assertNotEq(deployment.approvalGovernor, address(0));
        assertNotEq(deployment.quadraticGovernor, address(0));
        assertNotEq(deployment.governorGeneral, address(0));
        assertNotEq(deployment.timelock, address(0));

        // Check proxy settings
        FederatedBeaconProxy approvalProxy = FederatedBeaconProxy(payable(deployment.approvalGovernor));
        assertEq(approvalProxy.getBeacon(), factory.approvalGovBeacon());
        assertEq(approvalProxy.getAgencyAdmin(), agencyAdmin);
        assertFalse(approvalProxy.isOverridden());
        assertEq(approvalProxy.getCustomImplementation(), address(0));

        // Check governance wiring
        assertEq(ApprovalGovernor(deployment.approvalGovernor).governorGeneral(), deployment.governorGeneral);
        assertEq(ApprovalGovernor(deployment.approvalGovernor).owner(), agencyAdmin);
    }

    function test_FederatedAgency_FederalBeaconUpgrade_AutoPropagates() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        // Deploy Federal V3 implementation and upgrade federal beacon
        vm.startPrank(federalProtocolOwner);
        ApprovalGovernorV3 v3Impl = new ApprovalGovernorV3();
        UpgradeableBeacon(factory.approvalGovBeacon()).upgradeTo(address(v3Impl));
        vm.stopPrank();

        // The federated agency proxy immediately has the new federal feature without any agency action!
        string memory feat = ApprovalGovernorV3(deployment.approvalGovernor).federalFeatureV3();
        assertEq(feat, "FederalV3Active");
    }

    function test_FederatedAgency_SovereignOverride_CustomContract() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        FederatedBeaconProxy approvalProxy = FederatedBeaconProxy(payable(deployment.approvalGovernor));

        // Agency deploys custom sovereign governor
        MockCustomStageGovernor customGov = new MockCustomStageGovernor("CustomAgencyRuleV1");

        // Agency admin overrides the federal beacon
        vm.prank(agencyAdmin);
        approvalProxy.overrideImplementation(address(customGov));

        assertTrue(approvalProxy.isOverridden());
        assertEq(approvalProxy.getCustomImplementation(), address(customGov));

        // Calling through the proxy now returns the custom implementation's data!
        assertEq(MockCustomStageGovernor(deployment.approvalGovernor).stageId(), 99);
        assertEq(MockCustomStageGovernor(deployment.approvalGovernor).customAgencyFeature(), "SovereignAgencyV1");
    }

    function test_FederatedAgency_OverrideImmuneToFederalBeaconUpgrade() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        FederatedBeaconProxy approvalProxy = FederatedBeaconProxy(payable(deployment.approvalGovernor));

        // Agency overrides with custom governor
        MockCustomStageGovernor customGov = new MockCustomStageGovernor("CustomAgencyRuleV1");
        vm.prank(agencyAdmin);
        approvalProxy.overrideImplementation(address(customGov));

        // Federal protocol updates beacon to V3
        vm.startPrank(federalProtocolOwner);
        ApprovalGovernorV3 v3Impl = new ApprovalGovernorV3();
        UpgradeableBeacon(factory.approvalGovBeacon()).upgradeTo(address(v3Impl));
        vm.stopPrank();

        // The agency proxy is IMMUNE to the federal upgrade! Still running the custom logic
        assertEq(MockCustomStageGovernor(deployment.approvalGovernor).stageId(), 99);
        assertEq(MockCustomStageGovernor(deployment.approvalGovernor).customAgencyFeature(), "SovereignAgencyV1");
    }

    function test_FederatedAgency_ResetToFederalBeacon_RejoinsFederalStandard() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        FederatedBeaconProxy approvalProxy = FederatedBeaconProxy(payable(deployment.approvalGovernor));

        // 1. Override
        MockCustomStageGovernor customGov = new MockCustomStageGovernor("CustomAgencyRuleV1");
        vm.prank(agencyAdmin);
        approvalProxy.overrideImplementation(address(customGov));
        assertTrue(approvalProxy.isOverridden());

        // 2. Federal updates beacon to V3
        vm.startPrank(federalProtocolOwner);
        ApprovalGovernorV3 v3Impl = new ApprovalGovernorV3();
        UpgradeableBeacon(factory.approvalGovBeacon()).upgradeTo(address(v3Impl));
        vm.stopPrank();

        // 3. Agency decides to realign with Federal Standard
        vm.prank(agencyAdmin);
        approvalProxy.resetToFederalBeacon();

        assertFalse(approvalProxy.isOverridden());
        assertEq(approvalProxy.getCustomImplementation(), address(0));

        // Now proxy seamlessly executes Federal V3!
        assertEq(ApprovalGovernorV3(deployment.approvalGovernor).federalFeatureV3(), "FederalV3Active");
    }

    function test_FederatedAgency_RevertUnauthorizedOverride() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        FederatedBeaconProxy approvalProxy = FederatedBeaconProxy(payable(deployment.approvalGovernor));
        MockCustomStageGovernor customGov = new MockCustomStageGovernor("CustomAgencyRuleV1");

        // Attacker attempts override
        vm.prank(attacker);
        vm.expectRevert(FederatedBeaconProxy.UnauthorizedAgencyAdmin.selector);
        approvalProxy.overrideImplementation(address(customGov));

        // Attacker attempts reset
        vm.prank(attacker);
        vm.expectRevert(FederatedBeaconProxy.UnauthorizedAgencyAdmin.selector);
        approvalProxy.resetToFederalBeacon();
    }

    function test_FederatedAgency_ChangeAgencyAdmin() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        FederatedBeaconProxy approvalProxy = FederatedBeaconProxy(payable(deployment.approvalGovernor));
        address newAdmin = address(0x999);

        vm.prank(agencyAdmin);
        approvalProxy.changeAgencyAdmin(newAdmin);

        assertEq(approvalProxy.getAgencyAdmin(), newAdmin);

        // Old admin is now rejected
        MockCustomStageGovernor customGov = new MockCustomStageGovernor("CustomRule");
        vm.prank(agencyAdmin);
        vm.expectRevert(FederatedBeaconProxy.UnauthorizedAgencyAdmin.selector);
        approvalProxy.overrideImplementation(address(customGov));

        // New admin succeeds
        vm.prank(newAdmin);
        approvalProxy.overrideImplementation(address(customGov));
        assertTrue(approvalProxy.isOverridden());
    }

    function test_FederatedAgency_AdminCanCallImplementationFunctions() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory deployment = factory.deployFederatedAgencyDAO(config);

        // Agency admin calls implementation functions like setQuorumScore
        vm.prank(agencyAdmin);
        ApprovalGovernor(deployment.approvalGovernor).setQuorumScore(555);

        assertEq(ApprovalGovernor(deployment.approvalGovernor).quorumScore(), 555);
    }

    function test_Factory_DualDeploymentModes_BothOperational() public {
        ContractsFactory.AgencyDAOConfig memory config = _defaultAgencyConfig();

        // 1. Deploy Mode 1: Autonomous UUPS
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory uupsDAO = factory.deployAgencyDAO(config);
        assertEq(factory.totalDeployments(), 1);

        // 2. Deploy Mode 2: Federated Beacon
        vm.prank(agencyAdmin);
        ContractsFactory.AgencyDAODeployment memory federatedDAO = factory.deployFederatedAgencyDAO(config);
        assertEq(factory.totalDeployments(), 2);

        // Both are completely functional and isolated
        assertNotEq(uupsDAO.approvalGovernor, federatedDAO.approvalGovernor);
        assertFalse(FederatedBeaconProxy(payable(federatedDAO.approvalGovernor)).isOverridden());
    }
}
