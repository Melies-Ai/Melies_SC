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
     * @notice Deploys the MEL token contract with specified admin and initializes core functionality
     * @dev Constructor that sets up the ERC20 token with 8 decimals, pausable functionality,
     * access control, and EIP-2612 permit support. Grants DEFAULT_ADMIN_ROLE to specified admin.
     *
     * Token Configuration:
     * - Name: "Melies"
     * - Symbol: "MEL"
     * - Decimals: 8 (overridden from default 18)
     * - Max Supply: 1,000,000,000 MEL (1 billion tokens)
     * - Initial Supply: 0 (tokens minted as needed)
     *
     * Features Enabled:
     * - ERC20 standard compliance with 8 decimal precision
     * - Pausable transfers for emergency control
     * - Role-based access control (ADMIN, PAUSER, MINTER, BURNER roles)
     * - EIP-2612 permit functionality for gasless approvals
     * - Supply cap enforcement to prevent inflation
     *
     * Access Control Setup:
     * - DEFAULT_ADMIN_ROLE: Granted to defaultAdmin (can manage all other roles)
     * - Other roles (PAUSER, MINTER, BURNER) must be granted separately by admin
     *
     * Requirements:
     * - defaultAdmin cannot be the zero address (prevents bricking admin functions)
     *
     * @param defaultAdmin Address to receive DEFAULT_ADMIN_ROLE and manage other roles
     *
     * @custom:security-note Admin has full control over token functionality - use multisig
     * @custom:precision-note Uses 8 decimals instead of standard 18 for better UI/UX
     * @custom:gas-note Constructor cost includes role setup and multiple inheritance initialization
     *
     * No events emitted by constructor (OpenZeppelin handles role grant events).
     *
     * @custom:example
     * ```solidity
     * // Deploy with multisig as admin
     * address multisig = 0x123...;
     * Melies token = new Melies(multisig);
     *
     * // Admin can then grant operational roles
     * token.grantRole(token.MINTER_ROLE(), stakingContract);
     * token.grantRole(token.BURNER_ROLE(), distributorContract);
     * ```
     */
    constructor(
        address defaultAdmin
    ) ERC20("Melies", "MEL") ERC20Permit("Melies") {
        require(defaultAdmin != address(0), "Invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Returns the number of decimal places for MEL token precision
     * @dev Overrides ERC20 default of 18 decimals to use 8 decimals for MEL tokens.
     * This provides sufficient precision for financial calculations while maintaining
     * compatibility with traditional financial systems and reducing gas costs.
     *
     * Precision Design Rationale:
     * - 8 decimals matches traditional financial precision (like cents to dollars)
     * - Enables micro-transactions while preventing dust amounts
     * - Reduces gas costs compared to 18-decimal calculations
     * - Maintains precision for reward calculations and staking operations
     *
     * Impact on Token Operations:
     * - All token amounts are expressed with 8 decimal places
     * - Minimum transferable amount: 0.00000001 MEL
     * - Maximum supply: 1,000,000,000.00000000 MEL (1 billion tokens)
     * - Frontend applications must account for 8-decimal display
     *
     * @return 8 The number of decimal places for MEL token
     *
     * @custom:standard-override Overrides ERC20 standard default of 18 decimals
     * @custom:immutable This value is constant and cannot be changed after deployment
     *
     * @custom:example
     * ```solidity
     * uint8 melDecimals = melToken.decimals(); // Returns: 8
     *
     * // Token amount examples:
     * // 1 MEL = 100000000 (1 * 10^8)
     * // 0.5 MEL = 50000000 (0.5 * 10^8)
     * // 1000.12345678 MEL = 100012345678 (1000.12345678 * 10^8)
     * ```
     */
    function decimals() public pure override(ERC20) returns (uint8) {
        return 8;
    }

    /**
     * @notice Temporarily halts all MEL token transfers and operations for emergency situations
     * @dev Activates emergency pause mechanism that disables transfers, minting, and burning.
     * Critical safety feature for responding to security incidents, smart contract vulnerabilities,
     * or other emergency situations requiring immediate protocol suspension.
     *
     * Operations Affected When Paused:
     * - All ERC20 transfers (transfer, transferFrom)
     * - Token minting via mint() function
     * - Token burning via burn() function
     * - Any other pausable operations in connected contracts
     *
     * Operations NOT Affected:
     * - View functions (balanceOf, totalSupply, etc.)
     * - Administrative functions (role management)
     * - Contract deployment and initialization
     *
     * Emergency Use Cases:
     * - Smart contract vulnerabilities discovered
     * - Suspicious trading activity or market manipulation
     * - Bridge or oracle compromise affecting token security
     * - Regulatory compliance requirements
     * - Planned protocol upgrades requiring temporary suspension
     *
     * Requirements:
     * - Only callable by addresses with PAUSER_ROLE
     * - Contract must not already be paused
     * - Should be used sparingly and only for legitimate emergencies
     *
     * @custom:security-critical Emergency function for protocol safety
     * @custom:reversible Can be undone via unpause() function with same role
     * @custom:transparency All pause events are logged for public transparency
     *
     * State Changes:
     * - Sets internal paused state to true
     * - Blocks all pausable operations until unpause is called
     *
     * Emits:
     * - {Paused} event with the address that triggered the pause
     *
     * @custom:example
     * ```solidity
     * // Emergency pause due to security incident
     * melToken.pause();
     * // All transfers now blocked until unpause() is called
     * ```
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Restores normal MEL token operations after emergency pause has been resolved
     * @dev Deactivates emergency pause mechanism, re-enabling all previously blocked operations.
     * Critical recovery function for restoring protocol functionality after security incidents
     * or maintenance periods have been successfully addressed.
     *
     * Operations Restored When Unpaused:
     * - All ERC20 transfers (transfer, transferFrom) resume normal operation
     * - Token minting via mint() function becomes available again
     * - Token burning via burn() function becomes available again
     * - Connected contract operations dependent on MEL transfers resume
     *
     * Recovery Process:
     * 1. Verify that the underlying issue/emergency has been resolved
     * 2. Confirm all security measures are in place
     * 3. Execute unpause to restore normal operations
     * 4. Monitor for any unexpected behavior post-unpause
     *
     * Post-Unpause Monitoring:
     * - All previously paused operations immediately become available
     * - No gradual restoration period (instant full functionality)
     * - Users can immediately resume normal token interactions
     * - Connected protocols can resume dependent operations
     *
     * Use Cases for Unpausing:
     * - Security vulnerability has been patched and verified safe
     * - Market manipulation incident has been resolved
     * - Regulatory compliance issues have been addressed
     * - Planned maintenance or upgrade has completed successfully
     * - False alarm pause needs to be quickly reversed
     *
     * Requirements:
     * - Only callable by addresses with PAUSER_ROLE
     * - Contract must currently be in paused state
     * - Should only be used after confirming safety to resume operations
     *
     * @custom:security-critical Recovery function requiring careful verification before use
     * @custom:immediate-effect All operations resume instantly upon execution
     * @custom:monitoring-required Post-unpause monitoring recommended for safety
     *
     * State Changes:
     * - Sets internal paused state to false
     * - Immediately re-enables all pausable operations
     * - Restores full protocol functionality
     *
     * Emits:
     * - {Unpaused} event with the address that triggered the unpause
     *
     * @custom:example
     * ```solidity
     * // After confirming security issue is resolved
     * melToken.unpause();
     * // All transfers and operations immediately available again
     * ```
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Creates new MEL tokens and assigns them to a specified address
     * @dev Creates `amount` tokens and assigns them to `to`, increasing the total supply.
     * This function implements supply cap enforcement to prevent exceeding the maximum total supply.
     *
     * Requirements:
     * - The caller must have the `MINTER_ROLE`
     * - `to` cannot be the zero address
     * - The total supply after minting must not exceed `maxTotalSupply`
     *
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint (in wei, with 8 decimals)
     *
     * @custom:security-note This function enforces a hard cap on total supply to prevent inflation attacks
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
     * @notice Destroys MEL tokens from a specified account
     * @dev Destroys `amount` tokens from the specified account, reducing the total supply.
     * This function permanently removes tokens from circulation.
     *
     * Requirements:
     * - The caller must have the `BURNER_ROLE`
     * - `from` cannot be the zero address
     * - `from` must have at least `amount` tokens
     *
     * @param from The address from which to burn tokens
     * @param amount The amount of tokens to burn (in wei, with 8 decimals)
     *
     * @custom:security-note Only authorized contracts/addresses with BURNER_ROLE can burn tokens
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
