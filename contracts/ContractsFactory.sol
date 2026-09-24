// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./MemberToken.sol";
import "./ApprovalGovernor.sol";
import "./QuadraticGovernor.sol";
import "./GovernorGeneral.sol";
import "./FederatedBeaconProxy.sol";

/**
 * @title ContractsFactory
 * @dev Factory for deploying EnDAOsment federated DAO instances.
 * Enables an organization / independent agency to deploy a customized,
 * multi-stage governance ecosystem with ERC1155 member tokens, timelock,
 * and dual approval/quadratic voting governors.
 */
contract ContractsFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    struct AgencyDAOConfig {
        address agencyAdmin;
        string tokenUri;
        address crsManager;
        uint256 approvalQuorum;
        uint256 quadraticQuorum;
        uint32 timelockMinDelay;
        uint32 votingDelay;
        uint32 approvalPeriod;
        uint32 quadraticPeriod;
        uint256 proposalThreshold;
        uint256 defaultMemberTokenId;
    }

    struct AgencyDAODeployment {
        address memberToken;
        address timelock;
        address approvalGovernor;
        address quadraticGovernor;
        address governorGeneral;
    }

    address public memberTokenImpl;
    address public timelockImpl;
    address public approvalGovImpl;
    address public quadraticGovImpl;
    address public governorGeneralImpl;

    AgencyDAODeployment[] public allDeployments;
    mapping(address => AgencyDAODeployment[]) public deploymentsByAgency;

    address public memberTokenBeacon;
    address public approvalGovBeacon;
    address public quadraticGovBeacon;
    address public governorGeneralBeacon;

    event AgencyDAOCreated(
        address indexed agencyAdmin,
        address memberToken,
        address timelock,
        address approvalGovernor,
        address quadraticGovernor,
        address governorGeneral
    );

    event FederatedAgencyDAOCreated(
        address indexed agencyAdmin,
        address memberToken,
        address timelock,
        address approvalGovernor,
        address quadraticGovernor,
        address governorGeneral
    );

    event FederalBeaconsUpdated(
        address memberTokenBeacon,
        address approvalGovBeacon,
        address quadraticGovBeacon,
        address governorGeneralBeacon
    );

    event FederalBeaconsCreated(
        address memberTokenBeacon,
        address approvalGovBeacon,
        address quadraticGovBeacon,
        address governorGeneralBeacon,
        address indexed beaconOwner
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _memberTokenImpl,
        address _timelockImpl,
        address _approvalGovImpl,
        address _quadraticGovImpl,
        address _governorGeneralImpl
    ) public initializer {
        __Ownable_init(_owner);

        memberTokenImpl = _memberTokenImpl;
        timelockImpl = _timelockImpl;
        approvalGovImpl = _approvalGovImpl;
        quadraticGovImpl = _quadraticGovImpl;
        governorGeneralImpl = _governorGeneralImpl;
    }

    function setImplementations(
        address _memberTokenImpl,
        address _timelockImpl,
        address _approvalGovImpl,
        address _quadraticGovImpl,
        address _governorGeneralImpl
    ) external onlyOwner {
        memberTokenImpl = _memberTokenImpl;
        timelockImpl = _timelockImpl;
        approvalGovImpl = _approvalGovImpl;
        quadraticGovImpl = _quadraticGovImpl;
        governorGeneralImpl = _governorGeneralImpl;
    }

    /**
     * @notice Registers existing canonical UpgradeableBeacon addresses for the federated DAO modules.
     */
    function setFederalBeacons(
        address _memberTokenBeacon,
        address _approvalGovBeacon,
        address _quadraticGovBeacon,
        address _governorGeneralBeacon
    ) external onlyOwner {
        memberTokenBeacon = _memberTokenBeacon;
        approvalGovBeacon = _approvalGovBeacon;
        quadraticGovBeacon = _quadraticGovBeacon;
        governorGeneralBeacon = _governorGeneralBeacon;

        emit FederalBeaconsUpdated(
            _memberTokenBeacon,
            _approvalGovBeacon,
            _quadraticGovBeacon,
            _governorGeneralBeacon
        );
    }

    /**
     * @notice Deploys new canonical UpgradeableBeacon instances owned by beaconOwner.
     */
    function createFederalBeacons(address beaconOwner) external onlyOwner {
        require(memberTokenImpl != address(0), "Factory: zero memberTokenImpl");
        require(approvalGovImpl != address(0), "Factory: zero approvalGovImpl");
        require(quadraticGovImpl != address(0), "Factory: zero quadraticGovImpl");
        require(governorGeneralImpl != address(0), "Factory: zero governorGeneralImpl");
        require(beaconOwner != address(0), "Factory: zero beaconOwner");

        memberTokenBeacon = address(new UpgradeableBeacon(memberTokenImpl, beaconOwner));
        approvalGovBeacon = address(new UpgradeableBeacon(approvalGovImpl, beaconOwner));
        quadraticGovBeacon = address(new UpgradeableBeacon(quadraticGovImpl, beaconOwner));
        governorGeneralBeacon = address(new UpgradeableBeacon(governorGeneralImpl, beaconOwner));

        emit FederalBeaconsCreated(
            memberTokenBeacon,
            approvalGovBeacon,
            quadraticGovBeacon,
            governorGeneralBeacon,
            beaconOwner
        );
    }

    /**
     * @notice Deploys a customized DAO for an organization / independent agency.
     */
    function deployAgencyDAO(AgencyDAOConfig calldata config) external returns (AgencyDAODeployment memory deployment) {
        require(config.agencyAdmin != address(0), "Factory: zero admin");
        require(config.crsManager != address(0), "Factory: zero crsManager");

        deployment = _deployProxies(config);
        _wirePermissions(config.agencyAdmin, deployment);

        allDeployments.push(deployment);
        deploymentsByAgency[config.agencyAdmin].push(deployment);

        emit AgencyDAOCreated(
            config.agencyAdmin,
            deployment.memberToken,
            deployment.timelock,
            deployment.approvalGovernor,
            deployment.quadraticGovernor,
            deployment.governorGeneral
        );
    }

    function _deployProxies(AgencyDAOConfig calldata config) internal returns (AgencyDAODeployment memory deployment) {
        // 1. MemberToken
        bytes memory tokenInit = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (address(this), address(this), address(this), config.tokenUri)
        );
        deployment.memberToken = address(new ERC1967Proxy(memberTokenImpl, tokenInit));

        // 2. Timelock
        address[] memory emptyAddressArray = new address[](0);
        bytes memory timelockInit = abi.encodeCall(
            TimelockControllerUpgradeable.initialize,
            (config.timelockMinDelay, emptyAddressArray, emptyAddressArray, address(this))
        );
        deployment.timelock = address(new ERC1967Proxy(timelockImpl, timelockInit));

        // 3. ApprovalGovernor
        bytes memory approvalInit = abi.encodeCall(
            ApprovalGovernor.initialize,
            (address(this), deployment.memberToken, config.crsManager, config.approvalQuorum)
        );
        deployment.approvalGovernor = address(new ERC1967Proxy(approvalGovImpl, approvalInit));

        // 4. QuadraticGovernor
        bytes memory quadraticInit = abi.encodeCall(
            QuadraticGovernor.initialize,
            (address(this), deployment.memberToken, config.crsManager, config.quadraticQuorum)
        );
        deployment.quadraticGovernor = address(new ERC1967Proxy(quadraticGovImpl, quadraticInit));

        // 5. GovernorGeneral
        bytes memory generalInit = abi.encodeCall(
            GovernorGeneral.initialize,
            (
                deployment.memberToken,
                deployment.approvalGovernor,
                deployment.quadraticGovernor,
                payable(deployment.timelock),
                config.votingDelay,
                config.approvalPeriod,
                config.quadraticPeriod,
                config.proposalThreshold,
                config.defaultMemberTokenId
            )
        );
        deployment.governorGeneral = address(new ERC1967Proxy(governorGeneralImpl, generalInit));
    }

    /**
     * @notice Deploys a federated DAO for an agency using FederatedBeaconProxy.
     * The components track canonical Federal Beacons by default, but the agency administrator
     * retains sovereign rights to override any proxy with custom smart contracts.
     */
    function deployFederatedAgencyDAO(AgencyDAOConfig calldata config) external returns (AgencyDAODeployment memory deployment) {
        require(config.agencyAdmin != address(0), "Factory: zero admin");
        require(config.crsManager != address(0), "Factory: zero crsManager");
        require(memberTokenBeacon != address(0), "Factory: zero memberTokenBeacon");
        require(approvalGovBeacon != address(0), "Factory: zero approvalGovBeacon");
        require(quadraticGovBeacon != address(0), "Factory: zero quadraticGovBeacon");
        require(governorGeneralBeacon != address(0), "Factory: zero governorGeneralBeacon");

        deployment = _deployFederatedProxies(config);
        _wirePermissions(config.agencyAdmin, deployment);

        allDeployments.push(deployment);
        deploymentsByAgency[config.agencyAdmin].push(deployment);

        emit FederatedAgencyDAOCreated(
            config.agencyAdmin,
            deployment.memberToken,
            deployment.timelock,
            deployment.approvalGovernor,
            deployment.quadraticGovernor,
            deployment.governorGeneral
        );
    }

    function _deployFederatedProxies(AgencyDAOConfig calldata config) internal returns (AgencyDAODeployment memory deployment) {
        // 1. MemberToken (FederatedBeaconProxy)
        bytes memory tokenInit = abi.encodeCall(
            ERC1155TokenUpgradeable.initialize,
            (address(this), address(this), address(this), config.tokenUri)
        );
        deployment.memberToken = address(new FederatedBeaconProxy(memberTokenBeacon, config.agencyAdmin, tokenInit));

        // 2. Timelock (Autonomous ERC1967Proxy for dedicated agency treasury isolation)
        address[] memory emptyAddressArray = new address[](0);
        bytes memory timelockInit = abi.encodeCall(
            TimelockControllerUpgradeable.initialize,
            (config.timelockMinDelay, emptyAddressArray, emptyAddressArray, address(this))
        );
        deployment.timelock = address(new ERC1967Proxy(timelockImpl, timelockInit));

        // 3. ApprovalGovernor (FederatedBeaconProxy)
        bytes memory approvalInit = abi.encodeCall(
            ApprovalGovernor.initialize,
            (address(this), deployment.memberToken, config.crsManager, config.approvalQuorum)
        );
        deployment.approvalGovernor = address(new FederatedBeaconProxy(approvalGovBeacon, config.agencyAdmin, approvalInit));

        // 4. QuadraticGovernor (FederatedBeaconProxy)
        bytes memory quadraticInit = abi.encodeCall(
            QuadraticGovernor.initialize,
            (address(this), deployment.memberToken, config.crsManager, config.quadraticQuorum)
        );
        deployment.quadraticGovernor = address(new FederatedBeaconProxy(quadraticGovBeacon, config.agencyAdmin, quadraticInit));

        // 5. GovernorGeneral (FederatedBeaconProxy)
        bytes memory generalInit = abi.encodeCall(
            GovernorGeneral.initialize,
            (
                deployment.memberToken,
                deployment.approvalGovernor,
                deployment.quadraticGovernor,
                payable(deployment.timelock),
                config.votingDelay,
                config.approvalPeriod,
                config.quadraticPeriod,
                config.proposalThreshold,
                config.defaultMemberTokenId
            )
        );
        deployment.governorGeneral = address(new FederatedBeaconProxy(governorGeneralBeacon, config.agencyAdmin, generalInit));
    }

    function _wirePermissions(address agencyAdmin, AgencyDAODeployment memory deployment) internal {
        // Connect module governors to GovernorGeneral
        ApprovalGovernor(deployment.approvalGovernor).setGovernorGeneral(deployment.governorGeneral);
        ApprovalGovernor(deployment.approvalGovernor).transferOwnership(agencyAdmin);

        QuadraticGovernor(deployment.quadraticGovernor).setGovernorGeneral(deployment.governorGeneral);
        QuadraticGovernor(deployment.quadraticGovernor).transferOwnership(agencyAdmin);

        GovernorGeneral(deployment.governorGeneral).transferOwnership(agencyAdmin);

        // Configure Timelock roles
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(deployment.timelock));
        timelock.grantRole(timelock.PROPOSER_ROLE(), deployment.governorGeneral);
        timelock.grantRole(timelock.CANCELLER_ROLE(), deployment.governorGeneral);
        timelock.grantRole(timelock.CANCELLER_ROLE(), agencyAdmin);
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.grantRole(timelock.DEFAULT_ADMIN_ROLE(), agencyAdmin);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Configure MemberToken roles
        ERC1155TokenUpgradeable token = ERC1155TokenUpgradeable(deployment.memberToken);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), agencyAdmin);
        token.grantRole(token.MINTER_ROLE(), agencyAdmin);
        token.grantRole(token.UPGRADER_ROLE(), agencyAdmin);
        token.grantRole(token.URI_SETTER_ROLE(), agencyAdmin);
        token.renounceRole(token.MINTER_ROLE(), address(this));
        token.renounceRole(token.UPGRADER_ROLE(), address(this));
        token.renounceRole(token.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function totalDeployments() external view returns (uint256) {
        return allDeployments.length;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[40] private __gap;
}
