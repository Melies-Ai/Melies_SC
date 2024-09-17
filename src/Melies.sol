// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Melies (MEL) Token
 * @dev Implementation of the MEL token with pausable, mintable, and burnable features.
 * This contract extends ERC20 with additional functionality from OpenZeppelin libraries.
 */
contract Melies is ERC20, ERC20Pausable, AccessControl, ERC20Permit {
    // Role definitions using keccak256 hashes
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // Maximum total supply for the token
    uint256 private constant MAX_TOTAL_SUPPLY = 1000000000;

    /**
     * @dev Indicates an error related to the maximum market cap, defined in tokenomics. Used in mint.
     * @param amount Token amount attempted to mint
     * @param totalSupply Current total supply before minting
     */
    error ERC20MarketCapExceeded(uint256 amount, uint256 totalSupply);

    /**
     * @dev Constructor that sets up the token with initial roles
     * @param defaultAdmin Address to be granted the default admin role
     * @param pauser Address to be granted the pauser role
     * @param minter Address to be granted the minter role
     * @param burner Address to be granted the burner role
     */
    constructor(
        address defaultAdmin,
        address pauser,
        address minter,
        address burner
    ) ERC20("Melies", "MEL") ERC20Permit("Melies") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(BURNER_ROLE, burner);
    }

    /**
     * @dev Pauses all token transfers.
     * See {ERC20Pausable} and {Pausable-_pause}.
     * Requirements:
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     * See {ERC20Pausable} and {Pausable-_unpause}.
     * Requirements:
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     * See {ERC20-_mint}.
     * Requirements:
     * - the caller must have the `MINTER_ROLE`.
     * - the total supply after minting must not exceed MAX_TOTAL_SUPPLY.
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        uint256 totalSupply = totalSupply();
        if (amount + totalSupply > MAX_TOTAL_SUPPLY) {
            revert ERC20MarketCapExceeded(amount, totalSupply);
        }
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the specified account.
     * See {ERC20-_burn}.
     * Requirements:
     * - the caller must have the `BURNER_ROLE`.
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens.
     * @param from The address from which to burn tokens
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     * Calling conditions:
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
