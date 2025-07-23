// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./interfaces/IMelies.sol";

/**
 * @title Melies (MEL) Token
 * @dev Implementation of the MEL token with pausable, mintable, and burnable features.
 * This contract extends ERC20 with additional functionality from OpenZeppelin libraries.
 *
 * Features:
 * - ERC20 standard compliance with 8 decimals
 * - Pausable functionality for emergency stops
 * - Mintable tokens with role-based access control
 * - Burnable tokens with role-based access control
 * - Permit functionality for gasless approvals
 * - Maximum supply cap enforcement
 *
 * @author Melies Team
 */
contract Melies is ERC20, ERC20Pausable, AccessControl, ERC20Permit {
    // ============ CONSTANTS ============

    /// @dev Role for pausing/unpausing token transfers
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Role for minting new tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Role for burning tokens
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @dev Maximum total supply: 1 billion tokens with 8 decimals
    uint256 public constant maxTotalSupply = 1_000_000_000e8;

    // ============ ERRORS ============

    /**
     * @dev Indicates an error when attempting to mint tokens that would exceed the maximum supply
     * @param amount Token amount attempted to mint
     * @param totalSupply Current total supply before minting
     */
    error ERC20MarketCapExceeded(uint256 amount, uint256 totalSupply);

    // ============ CONSTRUCTOR ============

    /**
     * @dev Constructor that sets up the token with initial roles and metadata
     * @param defaultAdmin Address to be granted the default admin role
     *
     * Requirements:
     * - `defaultAdmin` cannot be the zero address
     */
    constructor(
        address defaultAdmin
    ) ERC20("Melies", "MEL") ERC20Permit("Melies") {
        require(defaultAdmin != address(0), "Invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @dev Overrides the decimals function to return 8 instead of the default 18
     * @return 8 The number of decimals for the token
     */
    function decimals() public pure override(ERC20) returns (uint8) {
        return 8;
    }

    /**
     * @dev Pauses all token transfers
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     * - The caller must have the `PAUSER_ROLE`
     *
     * Emits a {Paused} event.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     * - The caller must have the `PAUSER_ROLE`
     *
     * Emits an {Unpaused} event.
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `to`, increasing the total supply
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     * - The caller must have the `MINTER_ROLE`
     * - `to` cannot be the zero address
     * - The total supply after minting must not exceed `maxTotalSupply`
     *
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > maxTotalSupply) {
            revert ERC20MarketCapExceeded(amount, totalSupply());
        }
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the specified account
     *
     * See {ERC20-_burn}.
     *
     * Requirements:
     * - The caller must have the `BURNER_ROLE`
     * - `from` cannot be the zero address
     * - `from` must have at least `amount` tokens
     *
     * @param from The address from which to burn tokens
     * @param amount The amount of tokens to burn
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     */
    function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Hook that is called before any transfer of tokens
     *
     * This includes minting and burning. The function checks if the sender has
     * sufficient unlocked balance and if the contract is not paused.
     *
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param value The amount of tokens being transferred
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
