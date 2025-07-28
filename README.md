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

## Deployment

### Pre-Deployment Setup

Before deploying the contracts, you need to configure several important settings:

#### 1. Distribution Addresses Configuration

⚠️ **IMPORTANT**: The following addresses in the deployment scripts need to be updated with actual addresses before deployment:

**In `script/Melies.s.sol` (Mainnet):**

```solidity
// These are currently set to address(0) and MUST be updated
address constant COMMUNITY_ADDRESS = address(0); // Replace with actual address
address constant TREASURY_ADDRESS = address(0);  // Replace with actual address
address constant PARTNERS_ADDRESS = address(0);  // Replace with actual address
address constant TEAM_ADDRESS = address(0);      // Replace with actual address
address constant LIQUIDITY_ADDRESS = address(0); // Replace with actual address
address constant AI_SYSTEMS_ADDRESS = address(0);// Replace with actual address
```

**In `script/MeliesTestnet.s.sol` (Testnet):**

```solidity
// Update these with your testnet addresses for testing
address constant COMMUNITY_ADDRESS = 0x1111111111111111111111111111111111111111;
// ... etc
```

#### 2. Environment Variables Setup

Create a `.env` file in the project root with the following variables:

```bash
# Private key for deployment (without 0x prefix)
PRIVATE_KEY=your_deployer_private_key_here

# Etherscan API key for contract verification
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

#### 3. Network Configuration

The RPC URLs are configured in the `Makefile`. Update them if needed:

-   `SEPOLIA_RPC_URL` - Base Sepolia testnet RPC
-   `MAINNET_RPC_URL` - Base mainnet RPC

### Deployment Commands

```bash
# Deploy to local network
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $TESTNET_RPC --broadcast --verify
```

### Testing

```bash
# Run all tests
make test

# Run tests with gas report
make test-with-gas

# Run specific test file
forge test --match-contract MeliesTest

# Check test coverage (note: may require compilation fixes)
forge coverage
```

### Available Make Commands

```bash
make install         # Install dependencies
make build          # Compile contracts
make test           # Run all tests
make deploy-sepolia # Deploy to Base Sepolia testnet
make deploy-mainnet # Deploy to Base mainnet
make clean          # Clean build artifacts
make format         # Format code
make help           # Show available commands
```

## NatSpec Documentation Standards

### Current Status

The contracts have basic documentation but need comprehensive NatSpec tags for audit readiness. Here's the required documentation standard:

### Required NatSpec Tags

Every public/external function should include:

````solidity
/**
 * @notice User-friendly description of what the function does
 * @dev Technical details for developers (implementation notes, gas considerations, etc.)
 *
 * Requirements:
 * - List all requirements/preconditions
 * - Include access control requirements
 * - Note any state changes
 *
 * @param paramName Description of parameter (include units, ranges, etc.)
 * @param anotherParam Description of another parameter
 *
 * @return returnValue Description of return value (if any)
 *
 * @custom:security-note Any security-relevant information
 * @custom:gas-note Gas consumption notes (if significant)
 *
 * Emits a {EventName} event.
 *
 * @custom:example
 * ```solidity
 * // Example usage code
 * contract.function(param1, param2);
 * ```
 */
````

### Examples by Contract

#### 1. Melies.sol (Token Contract)

```solidity
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
function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE)
```

#### 2. MeliesStaking.sol (Staking Contract)

Functions needing comprehensive NatSpec:

-   `stake()` - Add precision factor details, duration explanations
-   `unstake()` - Add reward calculation details
-   `earlyUnstake()` - Add burn percentage calculations
-   `updateAccumulatedRewards()` - Add gas limit and batching details

#### 3. MeliesICO.sol (ICO Contract)

Functions needing comprehensive NatSpec:

-   `buyWithEth()` - Add slippage protection details
-   `buyWithUsdc()` - Add purchase limit explanations
-   `addSaleRound()` - Add parameter validation details
-   `endIco()` - Add refund mechanism explanations

#### 4. MeliesTokenDistributor.sol (Distribution Contract)

Functions needing comprehensive NatSpec:

-   `claimTokens()` - Add vesting calculation details
-   `claimAllTokensWithHaircut()` - Add haircut percentage calculations
-   `addAllocation()` - Add TGE and vesting parameter details

### Priority Functions for Documentation

**High Priority (Auditor Focus Areas):**

1. All token minting/burning functions
2. Staking reward calculations
3. ICO purchase mechanisms
4. Token distribution and vesting logic
5. Emergency/admin functions

**Medium Priority:**

1. View functions with complex calculations
2. Internal helper functions
3. Configuration functions

### Documentation Generation

After adding NatSpec tags, generate documentation:

```bash
# Generate documentation
make docs

# This creates documentation in docs/ folder
```

### Validation

To ensure documentation quality:

1. Every public/external function has `@notice`
2. Complex functions have detailed `@dev` sections
3. All parameters documented with units/ranges
4. Security-relevant functions have `@custom:security-note`
5. Example usage provided for key functions

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
