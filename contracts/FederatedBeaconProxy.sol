// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @title FederatedBeaconProxy
 * @notice An upgradeable proxy implementing the Federated Beacon pattern with sovereign agency overrides.
 * @dev By default, delegates all calls to the canonical Federal Beacon (`IBeacon.implementation()`).
 * An authorized agency administrator can override the federal beacon with a custom smart contract,
 * or revert back to the federal standard at any time.
 */
contract FederatedBeaconProxy is Proxy {
    event ImplementationOverridden(address indexed customImplementation);
    event FederalBeaconRestored(address indexed federalBeacon);

    error UnauthorizedAgencyAdmin();
    error InvalidCustomImplementation();
    error ZeroAdminAddress();

    /**
     * @notice Initializes the proxy with a canonical federal beacon and an agency admin.
     * @param beacon Address of the canonical Federal Beacon.
     * @param agencyAdmin Address of the agency administrator with sovereign override rights.
     * @param data Optional initialization calldata delegatecalled to the initial implementation.
     */
    constructor(address beacon, address agencyAdmin, bytes memory data) payable {
        if (agencyAdmin == address(0)) revert ZeroAdminAddress();
        ERC1967Utils.upgradeBeaconToAndCall(beacon, data);
        ERC1967Utils.changeAdmin(agencyAdmin);
    }

    /**
     * @notice Overrides the federal beacon with an agency-specific custom implementation.
     * @param customImpl Address of the custom logic contract.
     */
    function overrideImplementation(address customImpl) external {
        if (msg.sender != ERC1967Utils.getAdmin()) revert UnauthorizedAgencyAdmin();
        if (customImpl.code.length == 0) revert InvalidCustomImplementation();

        ERC1967Utils.upgradeToAndCall(customImpl, "");
        emit ImplementationOverridden(customImpl);
    }

    /**
     * @notice Clears any custom override and realigns the proxy with the federal beacon.
     */
    function resetToFederalBeacon() external {
        if (msg.sender != ERC1967Utils.getAdmin()) revert UnauthorizedAgencyAdmin();

        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = address(0);
        emit FederalBeaconRestored(ERC1967Utils.getBeacon());
    }

    /**
     * @notice Transfers sovereign agency admin rights to a new address.
     * @param newAdmin Address of the new agency administrator or timelock.
     */
    function changeAgencyAdmin(address newAdmin) external {
        if (msg.sender != ERC1967Utils.getAdmin()) revert UnauthorizedAgencyAdmin();
        if (newAdmin == address(0)) revert ZeroAdminAddress();

        ERC1967Utils.changeAdmin(newAdmin);
    }

    /**
     * @notice Checks whether the proxy is currently running an agency custom override.
     */
    function isOverridden() external view returns (bool) {
        return ERC1967Utils.getImplementation() != address(0);
    }

    /**
     * @notice Returns the custom override implementation address, or address(0) if on federal standard.
     */
    function getCustomImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /**
     * @notice Returns the canonical federal beacon address.
     */
    function getBeacon() external view returns (address) {
        return ERC1967Utils.getBeacon();
    }

    /**
     * @notice Returns the sovereign agency administrator address.
     */
    function getAgencyAdmin() external view returns (address) {
        return ERC1967Utils.getAdmin();
    }

    /**
     * @dev Resolves implementation address: returns custom implementation if overridden,
     * otherwise delegates to the canonical federal beacon.
     */
    function _implementation() internal view virtual override returns (address) {
        address custom = ERC1967Utils.getImplementation();
        if (custom != address(0)) {
            return custom;
        }
        return IBeacon(ERC1967Utils.getBeacon()).implementation();
    }
}
