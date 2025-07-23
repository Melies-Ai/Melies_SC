# Melies Smart Contract System

A comprehensive smart contract system for the Melies (MEL) token, implementing ICO, staking, and token distribution mechanisms with advanced vesting schedules.

## Overview

The Melies smart contract system consists of four main contracts that work together to provide a complete token ecosystem:

1. **Melies.sol** - The main ERC20 token contract
2. **MeliesICO.sol** - Initial Coin Offering management
3. **MeliesStaking.sol** - Token staking with rewards
4. **MeliesTokenDistributor.sol** - Token distribution and vesting

## Contract Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Melies.sol    │    │  MeliesICO.sol  │    │MeliesStaking.sol│
│   (ERC20 Token) │    │   (ICO Mgmt)    │    │  (Staking)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │MeliesTokenDist. │
                    │  (Distribution) │
                    └─────────────────┘
```

## Contracts

### 1. Melies.sol - Main Token Contract

**Purpose**: ERC20 token implementation with additional features

**Key Features**:

-   ERC20 standard compliance with 8 decimals
-   Pausable functionality for emergency stops
-   Mintable tokens with role-based access control
-   Burnable tokens with role-based access control
-   Permit functionality for gasless approvals
-   Maximum supply cap enforcement (1 billion tokens)

**Roles**:

-   `DEFAULT_ADMIN_ROLE`: Full administrative control
-   `PAUSER_ROLE`: Can pause/unpause token transfers
-   `MINTER_ROLE`: Can mint new tokens
-   `BURNER_ROLE`: Can burn tokens

**Key Functions**:

-   `mint(address to, uint256 amount)`: Mint new tokens
-   `burn(address from, uint256 amount)`: Burn tokens
-   `pause()` / `unpause()`: Emergency pause functionality

### 2. MeliesICO.sol - ICO Management

**Purpose**: Manages the Initial Coin Offering process

**Key Features**:

-   Multiple sale rounds (Seed, Private Sale, Public Sale)
-   Token purchases with ETH and USDC
-   Whitelist management for each round
-   Vesting schedules with cliff periods
-   Refund mechanism for failed rounds
-   Integration with Chainlink price feeds and Uniswap

**Sale Rounds**:

-   **Seed Round**: Early investors with longer vesting
-   **Private Sale**: Accredited investors
-   **Public Sale**: General public with shorter vesting

**Key Functions**:

-   `addSaleRound()`: Create new sale rounds
-   `buyWithEth()` / `buyWithUsdc()`: Purchase tokens
-   `addToWhitelist()` / `removeFromWhitelist()`: Manage whitelist
-   `endIco()`: End the ICO and enable claims
-   `refund()`: Request refunds for failed rounds

### 3. MeliesStaking.sol - Staking System

**Purpose**: Manages token staking with reward distribution

**Key Features**:

-   Multiple staking durations (0, 3, 6, 12 months)
-   Dynamic reward calculation based on staking duration
-   Compound rewards option for no-lock staking
-   Early unstaking with burn penalties
-   Daily reward distribution system
-   TGE-based reward calculations

**Staking Options**:

-   **No Lock (Index 0)**: Flexible staking, minimum 5,000 MEL
-   **3 Months (Index 1)**: 30% bonus multiplier
-   **6 Months (Index 2)**: 60% bonus multiplier
-   **12 Months (Index 3)**: 120% bonus multiplier
-   **12 Months VIP (Index 4)**: 200% bonus multiplier, minimum 200,000 MEL

**Key Functions**:

-   `stake()`: Stake tokens with specified duration
-   `unstake()`: Unstake tokens after lock period
-   `earlyUnstake()`: Unstake early with burn penalty
-   `claimRewards()`: Claim accumulated rewards
-   `updateAccumulatedRewards()`: Update rewards for all stakers

### 4. MeliesTokenDistributor.sol - Token Distribution

**Purpose**: Manages token distribution and vesting schedules

**Key Features**:

-   Comprehensive vesting schedules with cliffs
-   TGE (Token Generation Event) release percentages
-   Early claiming with haircut penalties
-   Dynamic vesting based on ICO performance
-   Unsold token distribution
-   Support for off-chain deals

**Initial Allocations**:

-   **Community Fund**: 200M tokens, 48 months vesting, 2.08% TGE
-   **Treasury**: 100M tokens, 48 months vesting, 5.00% TGE
-   **Partners & Advisors**: 100M tokens, 18 months vesting, 10.00% TGE
-   **Team**: 100M tokens, 12 months cliff, 20 months vesting, 0.00% TGE
-   **Liquidity**: 100M tokens, available at TGE, 100.00% TGE
-   **AI Systems**: 100M tokens, 18 months vesting, 10.00% TGE

**Key Functions**:

-   `addAllocation()`: Add new token allocations
-   `claimTokens()`: Claim vested tokens normally
-   `claimAllTokensWithHaircut()`: Claim all tokens with penalty
-   `distributeUnsoldTokens()`: Distribute unsold ICO tokens
-   `setTgeTimestamp()`: Set the TGE timestamp

## Tokenomics

### Total Supply

-   **Maximum Supply**: 1,000,000,000 MEL (1 billion tokens)
-   **Decimals**: 8

### Initial Distribution

-   **ICO Sales**: 300M tokens (30%)
-   **Community Fund**: 200M tokens (20%)
-   **Treasury**: 100M tokens (10%)
-   **Partners & Advisors**: 100M tokens (10%)
-   **Team**: 100M tokens (10%)
-   **Liquidity**: 100M tokens (10%)
-   **AI Systems**: 100M tokens (10%)

### Staking Rewards

-   **Annual Budget**: 2.28M tokens
-   **Daily Budget**: ~6,247 tokens
-   **Duration Multipliers**: 1x to 3x based on lock period

## Security Features

### Access Control

-   Role-based access control using OpenZeppelin's AccessControl
-   Separate roles for different administrative functions
-   Emergency pause functionality

### Reentrancy Protection

-   All external calls protected with ReentrancyGuard
-   Safe token transfers using SafeERC20

### Input Validation

-   Comprehensive parameter validation
-   Custom error messages for better gas efficiency
-   Bounds checking for all numerical inputs

### Emergency Functions

-   Emergency pause for all contracts
-   Emergency token withdrawal functions
-   Refund mechanisms for failed ICO rounds

## Development

### Prerequisites

-   Solidity ^0.8.20
-   OpenZeppelin Contracts ^5.0.0
-   Foundry for testing and deployment

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd Melies_SC

# Install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test
```

### Testing

```bash
# Run all tests
forge test

# Run tests with coverage
forge coverage

# Run specific test file
forge test --match-contract MeliesTest
```

### Deployment

```bash
# Deploy to local network
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $TESTNET_RPC --broadcast --verify
```

## Interfaces

The system includes comprehensive interfaces for all contracts:

-   `IMelies.sol`: Interface for the main token contract
-   `IMeliesICO.sol`: Interface for the ICO contract
-   `IMeliesStaking.sol`: Interface for the staking contract
-   `IMeliesTokenDistributor.sol`: Interface for the distributor contract

## Documentation

### Doxygen Comments

All contracts include comprehensive Doxygen-style comments for:

-   Function parameters and return values
-   Requirements and restrictions
-   Events emitted
-   Error conditions

### Code Organization

Contracts are organized with clear section separators:

-   Constants
-   State Variables
-   Constructor
-   Admin Functions
-   User Functions
-   Internal Functions
-   View Functions

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Support

For questions and support, please contact the Melies team or create an issue in the repository.
