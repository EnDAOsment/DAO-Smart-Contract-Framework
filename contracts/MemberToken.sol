// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @custom:security-contact ting@dcipher.xyz
/**
 * @title ERC1155TokenUpgradeable
 * @dev Soul-bound ERC1155 Member Token with checkpointed voting power for governance.
 * Tokens cannot be transferred between regular accounts once minted.
 */
contract ERC1155TokenUpgradeable is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    UUPSUpgradeable
{
    using Checkpoints for Checkpoints.Trace208;

    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Checkpoints per token ID per account: tokenId => account => Trace208
    mapping(uint256 => mapping(address => Checkpoints.Trace208)) private _checkpoints;

    error SoulboundTokenTransferDisabled();

    event DelegateVotesChanged(address indexed account, uint256 indexed tokenId, uint256 previousBalance, uint256 newBalance);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address minter, address upgrader, string memory uri_)
        public initializer
    {
        __ERC1155_init(uri_);
        __AccessControl_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(URI_SETTER_ROLE, defaultAdmin);
    }

    function setURI(string memory newuri) public onlyRole(URI_SETTER_ROLE) {
        _setURI(newuri);
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        onlyRole(MINTER_ROLE)
    {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyRole(MINTER_ROLE)
    {
        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @notice Returns past balance at a given block timepoint for snapshots.
     */
    function getPastBalanceOf(address account, uint256 id, uint256 timepoint) public view returns (uint256) {
        require(timepoint < clock(), "MemberToken: future lookup");
        return _checkpoints[id][account].upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    /**
     * @notice Current timepoint as block number.
     */
    function clock() public view virtual returns (uint48) {
        return SafeCast.toUint48(block.number);
    }

    /**
     * @notice Description of the clock mode.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        return "mode=blocknumber&finality=finalized";
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        // Enforce soul-bound token property: no direct peer-to-peer transfers
        if (from != address(0) && to != address(0)) {
            revert SoulboundTokenTransferDisabled();
        }

        super._update(from, to, ids, values);

        uint48 timepoint = clock();
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (from != address(0)) {
                uint208 fromBal = SafeCast.toUint208(balanceOf(from, id));
                _checkpoints[id][from].push(timepoint, fromBal);
            }
            if (to != address(0)) {
                uint208 toBal = SafeCast.toUint208(balanceOf(to, id));
                _checkpoints[id][to].push(timepoint, toBal);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    uint256[49] private __gap;
}
