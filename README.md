# Melies Token (MEL)

Melies Token (MEL) is an ERC20 token with advanced features including staking, ICO management, and token distribution mechanisms.

## Overview

The Melies ecosystem consists of several smart contracts that work together to provide:

-   ERC20 token with governance features (ERC20Votes)
-   Initial Coin Offering (ICO) with multiple sale rounds
-   Staking system with flexible lock periods and rewards
-   Token distribution with vesting schedules
-   Governance capabilities

## Smart Contracts

### Melies.sol

The main ERC20 token contract with:

-   8 decimal places
-   Pausable functionality
-   Role-based access control
-   ERC20Permit for gasless approvals
-   ERC20Votes for governance
-   Maximum supply of 100M tokens

### MeliesICO.sol

Manages the token sale with:

-   Multiple sale rounds
-   Support for ETH, USDC, and USDT payments
-   Whitelist functionality
-   Vesting schedules for purchased tokens
-   Refund mechanism if soft cap isn't reached

### MeliesStaking.sol

Handles token staking with:

-   Multiple lock periods (no lock, 30, 90, 180, 365 days)
-   Reward multipliers based on lock duration
-   Compound rewards option
-   Daily reward distribution
-   Voting power integration

### MeliesTokenDistributor.sol

Manages token distribution for:

-   Community Fund (45M tokens)
-   Foundation (30M tokens)
-   Partners & Advisors (25M tokens)
-   Team (20M tokens)
-   Liquidity (20M tokens)

## Features

-   **Role-Based Access**: Different roles for minting, burning, pausing, and admin functions
-   **Flexible Staking**: Users can choose different lock periods with corresponding reward multipliers
-   **ICO Management**: Multiple rounds with different prices and caps
-   **Vesting Schedules**: Customizable vesting periods with cliff durations
-   **Governance Integration**: Token holders and stakers can participate in governance

## Dependencies

-   OpenZeppelin Contracts v5.0.0
-   Chainlink Price Feeds
-   Uniswap V2 Interface

## Development

This project uses Solidity version 0.8.20 and requires the following dependencies:

-   OpenZeppelin Contracts
-   Chainlink Contracts
-   Uniswap V2 Periphery

## Security

The contracts include several security features:

-   Reentrancy protection
-   Role-based access control
-   Pausable functionality
-   Emergency withdrawal mechanisms
-   Slippage protection for ETH purchases

## License

MIT License
