// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMelies
 * @dev Interface for the Melies (MEL) token contract.
 * This interface defines the external functions, events, and constants
 * for the Melies ERC20 token with additional functionality.
 *
 * @author Melies Team
 */
interface IMelies {
    // ============ CONSTANTS ============

    /// @dev Role for pausing/unpausing token transfers
    function PAUSER_ROLE() external view returns (bytes32);

    /// @dev Role for minting new tokens
    function MINTER_ROLE() external view returns (bytes32);

    /// @dev Role for burning tokens
    function BURNER_ROLE() external view returns (bytes32);

    /// @dev Maximum total supply: 1 billion tokens with 8 decimals
    function maxTotalSupply() external view returns (uint256);

    // ============ FUNCTIONS ============

    /**
     * @dev Returns the number of decimals used to get its user representation
     * @return The number of decimals
     */
    function decimals() external pure returns (uint8);

    /**
     * @dev Returns the name of the token
     * @return The name of the token
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token
     * @return The symbol of the token
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the total supply of tokens
     * @return The total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the balance of tokens for a given account
     * @param account The address to query the balance for
     * @return The balance of the account
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Transfers tokens from the caller to a specified address
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the allowance given to a spender by an owner
     * @param owner The address that owns the tokens
     * @param spender The address that can spend the tokens
     * @return The amount of tokens the spender is allowed to spend
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Approves a spender to spend tokens on behalf of the caller
     * @param spender The address to approve
     * @param amount The amount of tokens to approve
     * @return True if the approval was successful
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Transfers tokens from one address to another using allowance
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @dev Pauses all token transfers
     *
     * Requirements:
     * - The caller must have the `PAUSER_ROLE`
     *
     * Emits a {Paused} event.
     */
    function pause() external;

    /**
     * @dev Unpauses all token transfers
     *
     * Requirements:
     * - The caller must have the `PAUSER_ROLE`
     *
     * Emits an {Unpaused} event.
     */
    function unpause() external;

    /**
     * @dev Creates `amount` tokens and assigns them to `to`, increasing the total supply
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
    function mint(address to, uint256 amount) external;

    /**
     * @dev Destroys `amount` tokens from the specified account
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
    function burn(address from, uint256 amount) external;

    /**
     * @dev Returns true if the contract is paused, false otherwise
     * @return True if the contract is paused
     */
    function paused() external view returns (bool);

    /**
     * @dev Returns true if an account has a specific role
     * @param role The role to check
     * @param account The account to check
     * @return True if the account has the role
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls the specified role
     * @param role The role to get the admin role for
     * @return The admin role
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants a role to an account
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes a role from an account
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Renounces a role from the caller
     * @param role The role to renounce
     */
    function renounceRole(bytes32 role) external;
}
