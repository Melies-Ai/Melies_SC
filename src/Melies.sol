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
    uint256 private constant MAX_TOTAL_SUPPLY = 1_000_000_000 * 1e8;

    // Sructure for locked tokens
    struct LockedTokens {
        uint256 amount;
        uint256 unlockTime;
    }

    // TGE date
    uint256 internal tgeTimestamp;

    // Mapping for locked balances
    mapping(address => LockedTokens[]) private _lockedTokens;

    /**
     * @dev Indicates an error related to the maximum market cap, defined in tokenomics. Used in mint.
     * @param amount Token amount attempted to mint
     * @param totalSupply Current total supply before minting
     */
    error ERC20MarketCapExceeded(uint256 amount, uint256 totalSupply);

    /**
     * @dev Error thrown when an account attempts to transfer more tokens than their unlocked balance.
     * @param available The amount of unlocked tokens available for transfer.
     * @param required The amount of tokens attempted to be transferred.
     */
    error InsufficientUnlockedBalance(uint256 available, uint256 required);

    /**
     * @dev Error thrown when attempting to release locked tokens but there are no tokens to release.
     */
    error NoTokensToRelease();

    /**
     * @dev Emitted when locked tokens are released.
     * @param account The address of the account that released the tokens.
     * @param amount The amount of tokens released.
     */
    event LockedTokensReleased(address indexed account, uint256 amount);

    /**
     * @dev Constructor that sets up the token with initial roles
     * @param defaultAdmin Address to be granted the default admin role
     * @param pauser Address to be granted the pauser role
     * @param minter Address to be granted the minter role
     * @param burner Address to be granted the burner role
     * @param initialTgeTimestamp The initial timestamp for the TGE date
     */
    constructor(
        address defaultAdmin,
        address pauser,
        address minter,
        address burner,
        uint256 initialTgeTimestamp
    ) ERC20("Melies", "MEL") ERC20Permit("Melies") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(BURNER_ROLE, burner);
        tgeTimestamp = initialTgeTimestamp;
    }

    /**
     * @dev Overrides the decimals function to return 8
     * @return 8
     */
    function decimals() public pure override returns (uint8) {
        return 8;
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
     * @dev Mints new tokens with a lock period.
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     * @param lockDuration The duration (in seconds) for which the tokens will be locked
     */
    function mintLocked(
        address to,
        uint256 amount,
        uint256 lockDuration
    ) public onlyRole(MINTER_ROLE) {
        uint256 totalSupply = totalSupply();
        if (amount + totalSupply > MAX_TOTAL_SUPPLY) {
            revert ERC20MarketCapExceeded(amount, totalSupply);
        }
        _mint(to, amount);
        _lockedTokens[to].push(
            LockedTokens({
                amount: amount,
                unlockTime: tgeTimestamp + lockDuration
            })
        );
    }

    /**
     * @dev Releases all locked tokens that have expired their lock period.
     */
    function releaseLocked() public {
        uint256 totalReleased = 0;
        uint256 i = 0;

        while (i < _lockedTokens[msg.sender].length) {
            LockedTokens storage lockedToken = _lockedTokens[msg.sender][i];

            if (block.timestamp >= lockedToken.unlockTime) {
                totalReleased += lockedToken.amount;

                // Remove the released token entry
                _lockedTokens[msg.sender][i] = _lockedTokens[msg.sender][
                    _lockedTokens[msg.sender].length - 1
                ];
                _lockedTokens[msg.sender].pop();
            } else {
                i++;
            }
        }

        if (totalReleased == 0) revert NoTokensToRelease();

        emit LockedTokensReleased(msg.sender, totalReleased);
    }

    /**
     * @dev Returns the total amount of locked tokens for an address.
     * @param account The address to check for locked tokens
     * @return The total amount of locked tokens
     */
    function getLockedBalance(address account) public view returns (uint256) {
        uint256 lockedBalance = 0;
        for (uint256 i = 0; i < _lockedTokens[account].length; i++) {
            lockedBalance += _lockedTokens[account][i].amount;
        }
        return lockedBalance;
    }

    /**
     * @dev Returns the amount of locked tokens that can be released for the given account.
     * @param account The address to check for releasable locked tokens
     * @return The total amount of locked tokens that can be released
     */
    function getReleasableAmount(
        address account
    ) public view returns (uint256) {
        uint256 releasableAmount = 0;

        for (uint256 i = 0; i < _lockedTokens[account].length; i++) {
            LockedTokens storage lockedToken = _lockedTokens[account][i];

            if (block.timestamp >= lockedToken.unlockTime) {
                releasableAmount += lockedToken.amount;
            }
        }

        return releasableAmount;
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
     * minting and burning. Checks if the sender has sufficient unlocked balance.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        if (from != address(0)) {
            uint256 availableBalance;
            if (_lockedTokens[from].length > 0) {
                if (getReleasableAmount(from) > 0) {
                    // Release all locked tokens before transfer
                    releaseLocked();
                }
                uint256 lockedBalance = getLockedBalance(from);
                availableBalance = balanceOf(from) - lockedBalance;
            } else {
                // No locked tokens, use the available balance
                availableBalance = balanceOf(from);
            }

            if (availableBalance < value) {
                revert InsufficientUnlockedBalance(availableBalance, value);
            }
        }
        super._update(from, to, value);
    }
}
