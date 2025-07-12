// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "./MeliesStaking.sol";

/**
 * @title Melies (MEL) Token
 * @dev Implementation of the MEL token with pausable, mintable, and burnable features.
 * This contract extends ERC20 with additional functionality from OpenZeppelin libraries.
 */
contract Melies is
    ERC20,
    ERC20Pausable,
    AccessControl,
    ERC20Permit,
    ERC20Votes
{
    // Role definitions using keccak256 hashes
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant STAKER_CONTRACT_ROLE =
        keccak256("STAKER_CONTRACT_ROLE");
    bytes32 public constant DAO_ADMIN_ROLE = keccak256("DAO_ADMIN_ROLE");

    // Maximum total supply for the token
    uint256 public constant MIN_MAX_TOTAL_SUPPLY = 1_000_000_000e8;
    uint256 public constant MAX_TOKEN_BURN = 900_000e8;
    uint256 public maxTotalSupply = 1_000_000_000e8;

    address public _stakingContract;

    /**
     * @dev Indicates an error related to the maximum market cap, defined in tokenomics. Used in mint.
     * @param amount Token amount attempted to mint
     * @param totalSupply Current total supply before minting
     */
    error ERC20MarketCapExceeded(uint256 amount, uint256 totalSupply);

    /**
     * @dev Indicates an error related to the maximum market cap, defined in tokenomics. Used in mint.
     */
    error BurnAmountExceeded();

    /**
     * @dev Error thrown when attempting to release locked tokens but there are no tokens to release.
     */
    error NoTokensToRelease();

    /**
     * @dev Error thrown when attempting to set an invalid max total supply.
     * @param newMaxSupply The invalid max supply amount attempted to be set.
     * @param currentTotalSupply The current total supply of tokens.
     */
    error InvalidMaxTotalSupply(
        uint256 newMaxSupply,
        uint256 currentTotalSupply
    );

    /**
     * @dev Error thrown when attempting to set the staking contract address more than once.
     */
    error StakingContractAlreadySet();

    /**
     * @dev Error thrown when attempting to get voting units without setting the staking contract address.
     */
    error StakingContractNotSet();

    /**
     * @dev Constructor that sets up the token with initial roles
     * @param defaultAdmin Address to be granted the default admin role
     */
    constructor(
        address defaultAdmin
    ) ERC20("Melies", "MEL") ERC20Permit("Melies") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @dev Sets the staking contract address.
     * @param stakingContract The address of the staking contract
     */
    function setStakingContract(
        address stakingContract
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_stakingContract != address(0)) {
            revert StakingContractAlreadySet();
        }
        _stakingContract = stakingContract;
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
     * - the total supply after minting must not exceed maxTotalSupply.
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        uint256 totalSupply = totalSupply();
        if (amount + totalSupply > maxTotalSupply) {
            revert ERC20MarketCapExceeded(amount, totalSupply);
        }
        _mint(to, amount);
    }

    /**
     * @dev Changes the maximum total supply of the token.
     * Requirements:
     * - the caller must have the `DAO_ADMIN_ROLE`.
     * - the new max supply must be greater than or equal to the current total supply.
     * @param newMaxSupply The new maximum total supply to set
     */
    function setMaxTotalSupply(
        uint256 newMaxSupply
    ) public onlyRole(DAO_ADMIN_ROLE) {
        uint256 currentTotalSupply = totalSupply();
        if (
            newMaxSupply < currentTotalSupply ||
            newMaxSupply < MIN_MAX_TOTAL_SUPPLY
        ) {
            revert InvalidMaxTotalSupply(newMaxSupply, currentTotalSupply);
        }
        maxTotalSupply = newMaxSupply;
    }

    /**
     * @dev Returns the voting units for an account.
     * @param account The address to get the voting units for
     * @return The voting units for the account
     */
    function _getVotingUnits(
        address account
    ) internal view virtual override returns (uint256) {
        if (_stakingContract == address(0)) {
            revert StakingContractNotSet();
        }
        uint256 totalStakes = MeliesStaking(_stakingContract)
            .getTotalUserStakes(account);
        return balanceOf(account) + totalStakes;
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
        if (amount > MAX_TOKEN_BURN) {
            revert BurnAmountExceeded();
        }
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
    ) internal override(ERC20, ERC20Pausable, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function updateVotingPowerOnStaking(
        address from,
        address to,
        uint256 value
    ) external onlyRole(STAKER_CONTRACT_ROLE) {
        _transferVotingUnits(from, to, value);
    }

    /**
     * @dev Overrides the nonces function to return the nonces from the ERC20Permit contract.
     * @param owner The address to get the nonces for
     * @return The nonces for the address
     */
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
