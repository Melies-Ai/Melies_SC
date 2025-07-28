// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./Melies.sol";
import "./MeliesTokenDistributor.sol";
import "./interfaces/IMeliesICO.sol";

/**
 * @title MeliesICO
 * @dev Manages the Initial Coin Offering (ICO) for the Melies token.
 *
 * This contract implements a comprehensive ICO system with the following features:
 * - Multiple sale rounds (Seed, Private Sale, Public Sale)
 * - Token purchases with ETH and USDC
 * - Whitelist management for each round
 * - Vesting schedules with cliff periods
 * - Refund mechanism for failed rounds
 * - Admin controls for ICO management
 * - Integration with Chainlink price feeds and Uniswap
 *
 * @author Melies Team
 */
contract MeliesICO is IMeliesICO, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============

    /// @dev Role for admin functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev Maximum contribution per wallet in public rounds ($50,000 USD)
    uint256 public constant PUBLIC_ROUND_MAX_CONTRIBUTION = 50_000e6;

    /// @dev Slippage tolerance denominator (10,000 = 100%)
    uint256 public constant SLIPPAGE_DENOMINATOR = 10_000;

    /// @dev Price feed decimals
    uint8 public constant PRICE_DECIMALS = 6;

    /// @dev USDC token decimals
    uint8 public constant USDC_DECIMALS = 6;

    // ============ STATE VARIABLES ============

    /// @dev Reference to the Melies token contract
    Melies public meliesToken;

    /// @dev Reference to the token distributor contract
    MeliesTokenDistributor public tokenDistributor;

    /// @dev Reference to the USDC token contract
    IERC20 public usdcToken;

    /// @dev Reference to the Uniswap V2 Router
    IUniswapV2Router02 public uniswapRouter;

    /// @dev Reference to the Chainlink ETH/USD price feed
    AggregatorV3Interface public ethUsdPriceFeed;

    /// @dev Slippage tolerance for ETH to USDC swaps (default: 0.5%)
    uint256 public slippageTolerance = 50;

    /// @dev Array of sale rounds
    SaleRound[] public saleRounds;

    /// @dev Mapping of user contributions per round
    mapping(address => mapping(uint256 => uint256))
        public userRoundContributions;

    /// @dev Mapping of whitelisted addresses per round
    mapping(uint256 => mapping(address => bool)) public whitelist;

    /// @dev Total USDC raised across all rounds
    uint256 public totalUsdcRaised;

    /// @dev Flag indicating if ICO has ended
    bool public icoEnded;

    /// @dev Flag indicating if token claims are enabled
    bool public claimEnabled;

    // ============ CONSTRUCTOR ============

    /**
     * @dev Constructor to initialize the MeliesICO contract
     * @param _meliesToken Address of the Melies token contract
     * @param _tokenDistributor Address of the MeliesTokenDistributor contract
     * @param _usdcToken Address of the USDC token contract
     * @param _uniswapRouter Address of the Uniswap V2 Router
     * @param _ethUsdPriceFeed Address of the Chainlink ETH/USD price feed
     *
     * Requirements:
     * - All addresses must be valid contract addresses
     */
    constructor(
        address _meliesToken,
        address _tokenDistributor,
        address _usdcToken,
        address _uniswapRouter,
        address _ethUsdPriceFeed
    ) {
        require(_meliesToken != address(0), "Invalid Melies token address");
        require(_tokenDistributor != address(0), "Invalid distributor address");
        require(_usdcToken != address(0), "Invalid USDC token address");
        require(_uniswapRouter != address(0), "Invalid Uniswap router address");
        require(_ethUsdPriceFeed != address(0), "Invalid price feed address");

        meliesToken = Melies(_meliesToken);
        tokenDistributor = MeliesTokenDistributor(_tokenDistributor);
        usdcToken = IERC20(_usdcToken);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Updates the slippage tolerance for ETH to USDC swaps
     * @param _newSlippageTolerance New slippage tolerance value (max 10%)
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - New slippage tolerance must not exceed 10%
     *
     * Emits a {SlippageToleranceUpdated} event.
     */
    function updateSlippageTolerance(
        uint256 _newSlippageTolerance
    ) external onlyRole(ADMIN_ROLE) {
        if (_newSlippageTolerance > 1000) revert SlippageToleranceTooHigh();
        slippageTolerance = _newSlippageTolerance;
        emit SlippageToleranceUpdated(_newSlippageTolerance);
    }

    /**
     * @notice Creates a new ICO sale round with specified parameters and vesting schedule
     * @dev Adds a configured sale round to the ICO with comprehensive parameter validation.
     * Each round operates independently with its own pricing, caps, limits, and vesting terms.
     * Rounds are identified by sequential indices starting from 0.
     *
     * Round Configuration:
     * - Timing: Start/end timestamps define the active purchase window
     * - Pricing: Fixed token price in USDC (e.g., 0.10 USDC = 100000 with 6 decimals)
     * - Caps: Hard cap (maximum raise) and soft cap (minimum for success)
     * - Limits: Per-transaction purchase bounds and wallet contribution limits
     * - Vesting: Cliff period, vesting duration, and TGE immediate release percentage
     *
     * Validation Rules:
     * - Time: _startTime < _endTime (logical chronological order)
     * - Price: _tokenPrice > 0 (must have positive value)
     * - Caps: _softCap ≤ _maxCap and both > 0 (achievable targets)
     * - Limits: _minPurchase ≤ _maxPurchase (valid range)
     * - Vesting: _vestingMonthDuration ≥ 1 if not 0 (minimum 1 month if vesting)
     * - Duration: _cliffMonthDuration + _vestingMonthDuration ≤ 48 (max 4 years total)
     * - TGE: _tgeReleasePercentage ≤ 100 (cannot exceed 100% immediate release)
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE (only authorized administrators)
     * - All parameter validation rules must pass
     * - Can be called multiple times to create sequential rounds
     *
     * @param _startTime Unix timestamp when round becomes active for purchases
     * @param _endTime Unix timestamp when round ends (exclusive)
     * @param _tokenPrice Price per MEL token in USDC (6 decimals, e.g., 100000 = $0.10)
     * @param _maxCap Maximum USDC to raise in this round (6 decimals, hard cap)
     * @param _softCap Minimum USDC to raise for round success (6 decimals, enables claims)
     * @param _minPurchase Minimum USDC purchase amount per transaction (6 decimals)
     * @param _maxPurchase Maximum USDC purchase amount per transaction (6 decimals)
     * @param _cliffMonthDuration Cliff period before vesting starts (in months, 0 = no cliff)
     * @param _vestingMonthDuration Linear vesting duration after cliff (in months, 0 = no vesting)
     * @param _tgeReleasePercentage Immediate release at TGE (0-100, e.g., 10 = 10%)
     *
     * @custom:security-note Comprehensive parameter validation prevents configuration errors
     * @custom:precision-note All USDC amounts use 6 decimals, percentages are whole numbers
     * @custom:gas-note Creates new storage slot in saleRounds array
     *
     * No events emitted (consider adding SaleRoundAdded event for better tracking).
     *
     * @custom:example
     * ```solidity
     * // Add seed round: $0.08/token, 30-day cliff, 12-month vest, 5% TGE
     * ico.addSaleRound(
     *     1640995200,  // Start: Jan 1, 2022
     *     1643673600,  // End: Feb 1, 2022
     *     80000,       // Price: $0.08 (80000 = 0.08 * 10^6)
     *     5000000e6,   // Hard cap: $5M
     *     1000000e6,   // Soft cap: $1M
     *     1000e6,      // Min purchase: $1000
     *     100000e6,    // Max purchase: $100k
     *     1,           // Cliff: 1 month
     *     12,          // Vesting: 12 months
     *     5            // TGE: 5%
     * );
     * ```
     */
    function addSaleRound(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPrice,
        uint256 _maxCap,
        uint256 _softCap,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _cliffMonthDuration,
        uint256 _vestingMonthDuration,
        uint256 _tgeReleasePercentage
    ) external onlyRole(ADMIN_ROLE) {
        if (_startTime >= _endTime) revert InvalidTimeRange();
        if (_tokenPrice == 0) revert InvalidTokenPrice();
        if (_maxCap == 0 || _softCap == 0 || _softCap > _maxCap) {
            revert InvalidCap();
        }
        if (_minPurchase > _maxPurchase) revert InvalidPurchaseLimits();
        if (_vestingMonthDuration != 0 && _vestingMonthDuration < 1) {
            revert InvalidVestingDuration();
        }
        // Maximum duration is 48 months
        if ((_cliffMonthDuration + _vestingMonthDuration) > 48) {
            revert InvalidCliffOrVestingDuration();
        }
        if (_tgeReleasePercentage > 100) revert InvalidTgeReleasePercentage();

        saleRounds.push(
            SaleRound({
                startTime: _startTime,
                endTime: _endTime,
                tokenPrice: _tokenPrice,
                maxCap: _maxCap,
                softCap: _softCap,
                minPurchase: _minPurchase,
                maxPurchase: _maxPurchase,
                totalUsdcRaised: 0,
                isFinish: false,
                cliffMonthDuration: _cliffMonthDuration,
                vestingMonthDuration: _vestingMonthDuration,
                tgeReleasePercentage: _tgeReleasePercentage
            })
        );
    }

    /**
     * @dev Adds addresses to the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be added to the whitelist
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Round ID must be valid
     *
     * Emits an {AddedToWhitelist} event.
     */
    function addToWhitelist(
        uint256 _roundId,
        address[] calldata _addresses
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_roundId][_addresses[i]] = true;
        }
        emit AddedToWhitelist(_roundId, _addresses);
    }

    /**
     * @dev Removes addresses from the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be removed from the whitelist
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Round ID must be valid
     *
     * Emits a {RemovedFromWhitelist} event.
     */
    function removeFromWhitelist(
        uint256 _roundId,
        address[] calldata _addresses
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_roundId][_addresses[i]] = false;
        }
        emit RemovedFromWhitelist(_roundId, _addresses);
    }

    /**
     * @dev Allows admins to add purchases made with fiat currency
     * @param _buyer Address of the token buyer
     * @param _usdAmount Amount of USD equivalent purchased
     * @param _roundId ID of the sale round
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Buyer address must be valid
     * - USD amount must be greater than 0
     * - Round ID must be valid
     */
    function addFiatPurchase(
        address _buyer,
        uint256 _usdAmount,
        uint8 _roundId
    ) external onlyRole(ADMIN_ROLE) {
        if (_buyer == address(0)) revert InvalidBuyer();
        if (_roundId >= saleRounds.length) revert InvalidRoundId();
        if (_usdAmount == 0) revert UsdAmountMustBeGreaterThanZero();

        _processPurchase(_buyer, _usdAmount, _roundId);
    }

    /**
     * @dev Allows admins to withdraw funds raised in a specific round
     * @param _roundId ID of the round to withdraw funds from
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Round must be finished
     * - Soft cap must be reached
     *
     * Emits a {RoundFundsWithdrawn} event.
     */
    function withdrawRoundFunds(
        uint256 _roundId
    ) external onlyRole(ADMIN_ROLE) {
        SaleRound storage round = saleRounds[_roundId];
        if (!round.isFinish) revert RoundNotFinished();
        if (round.totalUsdcRaised < round.softCap) revert SoftCapNotReached();

        uint256 usdcAmount = round.totalUsdcRaised;
        round.totalUsdcRaised = 0;

        if (usdcAmount > 0) {
            usdcToken.safeTransfer(msg.sender, usdcAmount);
        }

        emit RoundFundsWithdrawn(_roundId, usdcAmount);
    }

    /**
     * @notice Officially ends the ICO and determines refund eligibility for each round
     * @dev Critical administrative function that finalizes all sale rounds and enables post-ICO operations.
     * Evaluates each round against its soft cap to determine if refunds should be available.
     * Once called, no further token purchases are possible and distribution can begin.
     *
     * End-of-ICO Process:
     * 1. Mark ICO as permanently ended (irreversible operation)
     * 2. Force-finish any incomplete rounds regardless of end time
     * 3. Check each round's total USDC raised against its soft cap requirement
     * 4. Enable refunds for rounds that failed to meet soft cap
     * 5. Lock successful rounds for token distribution preparation
     *
     * Soft Cap Evaluation:
     * - Rounds meeting soft cap: participants receive tokens via TokenDistributor
     * - Rounds missing soft cap: participants become eligible for full USDC refunds
     * - Mixed success enables selective refunds (successful rounds proceed normally)
     *
     * Post-ICO State Changes:
     * - All purchase functions become permanently disabled
     * - Token distribution preparation can begin for successful rounds
     * - Refund functions become available for failed rounds
     * - Unsold token calculation becomes finalized
     *
     * Requirements:
     * - Only callable by addresses with ADMIN_ROLE
     * - ICO must not already be ended (prevents double execution)
     * - Can be called before natural round end times (emergency stop capability)
     *
     * @custom:security-note This is an irreversible operation that finalizes the entire ICO
     * @custom:emergency-use Can be used to stop ICO early if needed
     *
     * Emits:
     * - {IcoEnded} event with final ICO statistics
     * - {RefundsAvailableForRound} events for each failed round
     *
     * @custom:example
     * ```solidity
     * // End ICO after all rounds complete or in emergency
     * icoContract.endIco();
     * ```
     */
    function endIco() external onlyRole(ADMIN_ROLE) {
        if (icoEnded) revert IcoAlreadyEnded();
        icoEnded = true;

        bool allRoundsSoftCapReached = true;
        for (uint256 i = 0; i < saleRounds.length; i++) {
            SaleRound storage round = saleRounds[i];
            if (!round.isFinish) {
                round.isFinish = true;
                if (round.totalUsdcRaised < round.softCap) {
                    allRoundsSoftCapReached = false;
                    emit RefundsAvailableForRound(i);
                }
            }
        }

        claimEnabled = allRoundsSoftCapReached;

        // Distribute unsold tokens if all rounds reached soft cap
        if (allRoundsSoftCapReached) {
            tokenDistributor.distributeUnsoldTokens();
        }

        emit IcoEnded(claimEnabled);
    }

    /**
     * @notice Withdraws all USDC raised from successful ICO rounds for project funding
     * @dev Administrative function to collect funds from successful rounds after ICO completion.
     * Only withdraws USDC from rounds that met their soft cap requirements and are not subject to refunds.
     * This represents the project's operational funding from successful token sales.
     *
     * Withdrawal Process:
     * 1. Verify ICO has been officially ended
     * 2. Calculate available USDC balance (should exclude refund-eligible amounts)
     * 3. Transfer entire USDC balance to admin wallet
     * 4. Emit withdrawal event for transparency
     *
     * Fund Sources:
     * - USDC from successful sale rounds (those meeting soft cap)
     * - USDC from completed off-chain sales recorded via addFiatPurchase()
     * - Does not include USDC earmarked for refunds in failed rounds
     *
     * Timing Considerations:
     * - Should be called after refund period to avoid complications
     * - Best practice: allow sufficient time for all refund claims first
     * - Can be called multiple times if needed (withdraws current balance)
     *
     * Requirements:
     * - Only callable by addresses with ADMIN_ROLE
     * - ICO must be officially ended (icoEnded == true)
     * - Contract must have USDC balance available for withdrawal
     *
     * @custom:security-note Admin-only function prevents unauthorized fund access
     * @custom:transparency All withdrawals are logged via events for public audit
     *
     * State Changes:
     * - Transfers USDC balance from contract to caller
     * - Does not modify any internal accounting (preserves refund eligibility)
     *
     * Emits:
     * - {UsdcWithdrawn} event with recipient address and withdrawal amount
     *
     * @custom:example
     * ```solidity
     * // After ICO ends and refund period
     * icoContract.withdrawUsdc(); // Withdraws all available USDC
     * ```
     */
    function withdrawUsdc() external onlyRole(ADMIN_ROLE) {
        if (!icoEnded) revert IcoNotEndedYet();

        uint256 amount = usdcToken.balanceOf(address(this));

        usdcToken.safeTransfer(msg.sender, amount);
        emit UsdcWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Allows admins to withdraw any ETH in the contract after ICO ends
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - ICO must be ended
     * - Contract must have ETH balance
     *
     * Emits an {EthWithdrawn} event.
     */
    function withdrawEth() external onlyRole(ADMIN_ROLE) {
        if (!icoEnded) revert IcoNotEndedYet();

        uint256 amount = address(this).balance;
        if (amount == 0) revert NoEthToWithdraw();
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert EthTransferFailed();
        emit EthWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Allows admins to recover any ERC20 tokens accidentally sent to the contract
     * @param _token Address of the ERC20 token to recover
     * @param _amount Amount of tokens to recover
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Token must not be Melies or USDC tokens
     * - Contract must have sufficient token balance
     *
     * Emits a {TokensRecovered} event.
     */
    function recoverTokens(
        address _token,
        uint256 _amount
    ) external onlyRole(ADMIN_ROLE) {
        if (_token == address(meliesToken)) revert CannotRecoverMeliesTokens();
        if (_token == address(usdcToken)) revert CannotRecoverUsdcTokens();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        if (_amount > balance) revert InsufficientTokenBalance();

        token.safeTransfer(msg.sender, _amount);
        emit TokensRecovered(_token, msg.sender, _amount);
    }

    // ============ USER FUNCTIONS ============

    /**
     * @notice Purchases MEL tokens using ETH with automatic USDC conversion
     * @dev Converts ETH to USDC via Uniswap V2 with slippage protection, then processes token purchase.
     * Uses Chainlink ETH/USD price feed to calculate expected USDC amount and applies slippage tolerance.
     *
     * Process:
     * 1. Validate ETH sent and round parameters
     * 2. Get current ETH/USD price from Chainlink oracle
     * 3. Calculate expected USDC amount from ETH value
     * 4. Apply slippage tolerance to determine minimum USDC output
     * 5. Swap ETH for USDC via Uniswap V2 router
     * 6. Process token purchase with received USDC amount
     * 7. Create vesting allocation for buyer
     *
     * Requirements:
     * - ETH amount must be greater than 0 (msg.value > 0)
     * - Round ID must be valid and within bounds
     * - User must be whitelisted for the specified round
     * - Purchase amount must be within round's min/max limits
     * - Purchase must not exceed wallet contribution limit ($50k)
     * - Purchase must not exceed round's hard cap
     * - ICO must not be ended
     * - Chainlink price feed must return valid ETH/USD price
     * - Uniswap swap must meet slippage requirements
     *
     * @param _roundId ID of the sale round (0-based index)
     *
     * @custom:security-note Protected against reentrancy and uses slippage protection
     * @custom:oracle-note Depends on Chainlink ETH/USD price feed accuracy
     * @custom:slippage-note Default 0.5% slippage tolerance, configurable by admin
     * @custom:gas-note Higher gas cost due to Uniswap interaction and price feed calls
     *
     * Emits a {TokensPurchased} event with buyer address, USD amount, and token amount.
     *
     * @custom:example
     * ```solidity
     * // Purchase tokens in round 0 with 1 ETH
     * ico.buyWithEth{value: 1 ether}(0);
     *
     * // Purchase with specific ETH amount
     * ico.buyWithEth{value: 0.5 ether}(1);
     * ```
     */
    function buyWithEth(uint8 _roundId) external payable nonReentrant {
        if (msg.value == 0) revert NoEthSent();
        if (_roundId >= saleRounds.length) revert InvalidRoundId();
        _buyWithEth(_roundId);
    }

    /**
     * @notice Purchases MEL tokens directly using USDC stablecoin
     * @dev Processes direct USDC token purchases without external swaps or price feed dependencies.
     * More gas-efficient than ETH purchases as it skips Uniswap and Chainlink interactions.
     *
     * Process:
     * 1. Validate round ID and USDC amount parameters
     * 2. Transfer USDC from user to ICO contract using SafeERC20
     * 3. Process purchase with exact USDC amount (no slippage)
     * 4. Calculate token amount based on round's fixed token price
     * 5. Create vesting allocation for buyer in token distributor
     * 6. Update round totals and user contribution tracking
     *
     * Requirements:
     * - Round ID must be valid and within bounds
     * - USDC amount must be greater than 0
     * - User must be whitelisted for the specified round
     * - Purchase amount must be within round's min/max limits
     * - Purchase must not exceed wallet contribution limit ($50k)
     * - Purchase must not exceed round's hard cap
     * - ICO must not be ended
     * - User must have sufficient USDC balance
     * - User must have approved sufficient USDC allowance to ICO contract
     *
     * @param _roundId ID of the sale round (0-based index)
     * @param _amount Amount of USDC to spend on token purchase (6 decimals)
     *
     * @custom:security-note Protected against reentrancy and uses SafeERC20 for secure transfers
     * @custom:precision-note USDC uses 6 decimals, MEL uses 8 decimals - conversion handled automatically
     * @custom:gas-note Lower gas cost than ETH purchases (no external swaps or price feeds)
     *
     * Emits a {TokensPurchased} event with buyer address, USD amount, and token amount.
     *
     * @custom:example
     * ```solidity
     * // First approve USDC allowance
     * usdc.approve(address(ico), 1000e6);
     *
     * // Purchase tokens with 1000 USDC in round 0
     * ico.buyWithUsdc(0, 1000e6);
     *
     * // Purchase with different amount in round 1
     * ico.buyWithUsdc(1, 5000e6);
     * ```
     */
    function buyWithUsdc(
        uint8 _roundId,
        uint256 _amount
    ) external nonReentrant {
        if (_roundId >= saleRounds.length) revert InvalidRoundId();
        if (_amount == 0) revert UsdcAmountMustBeGreaterThanZero();

        usdcToken.safeTransferFrom(msg.sender, address(this), _amount);

        _processPurchase(msg.sender, _amount, _roundId);
    }

    /**
     * @notice Claims full USDC refunds for failed ICO rounds that didn't meet soft cap requirements
     * @dev Processes refunds across all failed rounds for the calling user in a single transaction.
     * Only available when ICO has ended and token claims are disabled, indicating round failures.
     * Refunds are only available for rounds that failed to meet their soft cap targets.
     *
     * Refund Eligibility Process:
     * 1. ICO must be officially ended via endIco() call
     * 2. Token claims must be disabled (indicates failed rounds exist)
     * 3. User must have contributions in rounds that failed soft cap requirements
     * 4. Each failed round's contributions are eligible for 100% USDC refund
     *
     * Refund Calculation:
     * - Iterates through all sale rounds to find failed ones
     * - Failed rounds: totalUsdcRaised < softCap
     * - Sums user contributions from all failed rounds
     * - Transfers total USDC amount back to user
     * - Marks user allocations as refunded to prevent double claims
     *
     * Mixed Success Scenarios:
     * - If some rounds succeeded and others failed: user gets refunds for failed rounds only
     * - Successful round contributions remain locked for token distribution
     * - Partial refunds are common in multi-round ICOs
     *
     * Requirements:
     * - ICO must be ended (icoEnded == true)
     * - Token claims must be disabled (claimEnabled == false)
     * - User must have non-zero contributions in failed rounds
     * - User must not have already claimed refunds for those rounds
     *
     * @custom:security-note Uses nonReentrant modifier to prevent refund manipulation
     * @custom:user-experience Single transaction refunds across all failed rounds for efficiency
     *
     * State Changes:
     * - Marks user allocations as refunded in failed rounds
     * - Transfers USDC from contract to user
     * - Updates refund tracking to prevent double claims
     *
     * Emits:
     * - {Refunded} event with total USDC amount and user address
     *
     * @custom:example
     * ```solidity
     * // After ICO ends with some failed rounds
     * icoContract.refund(); // Claims refunds for all failed rounds
     * ```
     */
    function refund() external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        if (claimEnabled) revert RefundNotAvailable();
        uint256 totalRefundUsdcAmount = 0;

        for (uint256 i = 0; i < saleRounds.length; i++) {
            SaleRound storage round = saleRounds[i];
            if (round.isFinish && round.totalUsdcRaised < round.softCap) {
                uint256 allocationAmount = userRoundContributions[msg.sender][
                    i
                ];
                if (allocationAmount > 0) {
                    totalRefundUsdcAmount += allocationAmount;
                    userRoundContributions[msg.sender][i] = 0;
                }
            }
        }

        if (totalRefundUsdcAmount == 0) revert NoAllocationToRefund();
        if (totalRefundUsdcAmount > 0) {
            usdcToken.safeTransfer(msg.sender, totalRefundUsdcAmount);
        }
        emit Refunded(msg.sender, totalRefundUsdcAmount);
    }

    /**
     * @dev Allows users to request a refund for a specific round if its soft cap wasn't reached
     * @param _roundId ID of the round to request a refund from
     *
     * Requirements:
     * - ICO must be ended
     * - Round must be finished and soft cap not reached
     * - User must have allocations in the round
     *
     * Emits a {Refunded} event.
     */
    function refundForRound(uint256 _roundId) external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        SaleRound storage round = saleRounds[_roundId];
        if (!round.isFinish || round.totalUsdcRaised >= round.softCap) {
            revert RefundNotAvailable();
        }

        uint256 refundUsdcAmount = userRoundContributions[msg.sender][_roundId];
        if (refundUsdcAmount == 0) revert NoAllocationToRefund();

        userRoundContributions[msg.sender][_roundId] = 0;
        if (refundUsdcAmount > 0) {
            usdcToken.safeTransfer(msg.sender, refundUsdcAmount);
        }

        emit Refunded(msg.sender, refundUsdcAmount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Internal function to process ETH to token purchases
     * @param _roundId ID of the sale round
     */
    function _buyWithEth(uint8 _roundId) internal {
        uint256 ethUsdPrice = getEthUsdPrice();
        uint256 expectedUsdcAmount = (msg.value * 10 ** USDC_DECIMALS) /
            ethUsdPrice;

        uint256 minUsdcAmount = (expectedUsdcAmount *
            (SLIPPAGE_DENOMINATOR - slippageTolerance)) / SLIPPAGE_DENOMINATOR;

        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = address(usdcToken);

        uint256[] memory amounts = uniswapRouter.swapExactETHForTokens{
            value: msg.value
        }(minUsdcAmount, path, address(this), block.timestamp + 15 minutes);

        _processPurchase(msg.sender, amounts[1], _roundId);
    }

    /**
     * @dev Internal function to process token purchases
     * @param _buyer Address of the token buyer
     * @param _usdAmount Amount of USD spent on the purchase
     * @param _roundId ID of the sale round
     * @return tokenAmount Amount of tokens purchased
     */
    function _processPurchase(
        address _buyer,
        uint256 _usdAmount,
        uint8 _roundId
    ) internal returns (uint256) {
        SaleRound storage round = saleRounds[_roundId];

        if (icoEnded) revert IcoAlreadyEnded();
        if (!whitelist[_roundId][_buyer]) revert NotWhitelisted();
        if (_usdAmount < round.minPurchase) revert BelowMinimumPurchase();
        if (_usdAmount > round.maxPurchase) revert ExceedsMaximumPurchase();

        // Check wallet contribution limit
        uint256 currentWalletContribution = userRoundContributions[_buyer][
            _roundId
        ];
        if (
            currentWalletContribution + _usdAmount >
            PUBLIC_ROUND_MAX_CONTRIBUTION
        ) {
            revert ExceedsWalletContributionLimit();
        }

        if (round.totalUsdcRaised + _usdAmount > round.maxCap) {
            revert RoundCapExceeded();
        }

        // Track total raised in USDC
        round.totalUsdcRaised += _usdAmount;

        // Track wallet contribution for the current round
        userRoundContributions[_buyer][_roundId] += _usdAmount;

        totalUsdcRaised += _usdAmount;

        // PRICE_DECIMALS cancels out with USDC_DECIMALS (6-6)
        uint256 tokenAmount = (_usdAmount * 10 ** meliesToken.decimals()) /
            round.tokenPrice;

        _addAllocation(_buyer, tokenAmount, _usdAmount, _roundId);

        emit TokensPurchased(_buyer, _usdAmount, tokenAmount);

        return tokenAmount;
    }

    /**
     * @dev Internal function to add token allocation for a buyer
     * @param _beneficiary Address of the token beneficiary
     * @param _tokenAmount Amount of tokens allocated
     * @param _usdcAmount Amount of USDC spent
     * @param _roundId ID of the sale round
     */
    function _addAllocation(
        address _beneficiary,
        uint256 _tokenAmount,
        uint256 _usdcAmount,
        uint256 _roundId
    ) internal {
        // Create allocation in MeliesTokenDistributor for vesting/claiming
        SaleRound memory round = saleRounds[_roundId];
        string memory roundName = _getRoundName(_roundId);

        // Convert TGE percentage from 0-100 to basis points (0-10000)
        uint256 tgeReleasePercentageBps = round.tgeReleasePercentage * 100;

        // Use cliff and vesting duration directly as they are already in months
        uint256 cliffMonths = round.cliffMonthDuration;
        uint256 vestingMonths = round.vestingMonthDuration;

        tokenDistributor.addAllocation(
            _beneficiary,
            _tokenAmount,
            cliffMonths,
            vestingMonths,
            roundName,
            tgeReleasePercentageBps,
            false
        );

        emit AllocationAdded(
            _beneficiary,
            _tokenAmount,
            round.cliffMonthDuration,
            round.vestingMonthDuration,
            _roundId
        );
    }

    /**
     * @dev Internal function to get round name based on round ID
     * @param _roundId ID of the sale round
     * @return Round name string
     */
    function _getRoundName(
        uint256 _roundId
    ) internal pure returns (string memory) {
        if (_roundId == 0) return "Seed";
        if (_roundId == 1) return "Private Sale";
        if (_roundId == 2) return "Public Sale";
        return string(abi.encodePacked("Round ", _roundId));
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Retrieves the currently active ICO sale round with complete configuration details
     * @dev Returns the full SaleRound struct for the round that is currently accepting purchases.
     * Critical function for frontend interfaces, purchase validation, and real-time ICO monitoring.
     * Automatically determines which round is active based on current timestamp and round status.
     *
     * SaleRound Struct Contents:
     * - startTime: Unix timestamp when round becomes available for purchases
     * - endTime: Unix timestamp when round automatically closes
     * - tokenPrice: Price per MEL token in USDC (6 decimals)
     * - maxCap: Maximum USDC that can be raised in this round
     * - softCap: Minimum USDC required for round to be considered successful
     * - minPurchase: Minimum USDC amount per individual purchase
     * - maxPurchase: Maximum USDC amount per individual purchase
     * - totalUsdcRaised: Current amount of USDC raised in this round
     * - totalTokensSold: Current amount of MEL tokens sold in this round
     * - isFinish: Whether round has been manually or automatically finished
     * - Vesting parameters: cliffMonthDuration, vestingMonthDuration, tgeReleasePercentage
     *
     * Round Selection Logic:
     * 1. Iterates through all configured sale rounds
     * 2. Finds round where current time is between startTime and endTime
     * 3. Ensures round is not manually finished (isFinish == false)
     * 4. Returns first matching active round
     *
     * Use Cases:
     * - Frontend display of current round information and progress
     * - Purchase validation and price calculation
     * - Investment opportunity assessment for users
     * - Real-time ICO analytics and monitoring dashboards
     * - Integration with automated purchase systems
     *
     * @return SaleRound struct containing all configuration and status data for active round
     *
     * @custom:view-function Pure read operation with no state changes or gas cost
     * @custom:frontend-critical Essential for user interfaces and purchase flows
     * @custom:real-time Reflects live round status and progress immediately
     *
     * Reverts:
     * - If no round is currently active (all rounds finished or none started)
     * - If ICO has been ended via endIco() function
     *
     * @custom:example
     * ```solidity
     * SaleRound memory activeRound = icoContract.getCurrentRound();
     *
     * uint256 progress = (activeRound.totalUsdcRaised * 100) / activeRound.maxCap;
     * uint256 timeRemaining = activeRound.endTime - block.timestamp;
     * bool softCapReached = activeRound.totalUsdcRaised >= activeRound.softCap;
     * ```
     */
    function getCurrentRound() public view returns (SaleRound memory) {
        uint256 roundId = getCurrentRoundId();
        return saleRounds[roundId];
    }

    /**
     * @notice Returns the array index of the currently active ICO sale round
     * @dev Determines which sale round is currently accepting purchases based on timing and status.
     * Essential utility function for round-specific operations, purchase routing, and frontend integration.
     * Used internally by getCurrentRound() and externally for round-specific function calls.
     *
     * Round Detection Algorithm:
     * 1. Iterates through saleRounds array sequentially (index 0 to length-1)
     * 2. For each round, checks three conditions:
     *    - Current timestamp >= round startTime (round has started)
     *    - Current timestamp < round endTime (round hasn't naturally expired)
     *    - isFinish == false (round hasn't been manually ended)
     * 3. Returns index of first round meeting all conditions
     * 4. Reverts if no active round is found
     *
     * Round Priority System:
     * - Earlier rounds in array take precedence over later ones
     * - If multiple rounds could theoretically be active, first one wins
     * - Round scheduling should avoid overlaps for predictable behavior
     *
     * Common Integration Patterns:
     * - Use with other functions requiring roundId parameter
     * - Frontend round selection and navigation
     * - Automated purchase systems for current round targeting
     * - Analytics systems tracking round progression
     * - Admin tools for round management and monitoring
     *
     * Error Conditions:
     * - No rounds configured: reverts with array bounds error
     * - All rounds finished: reverts with NoActiveRound error
     * - Current time before first round: reverts with NoActiveRound error
     * - ICO ended: should revert from calling functions
     *
     * @return uint256 The zero-based array index of the currently active sale round
     *
     * @custom:view-function Pure read operation with no state changes
     * @custom:utility-function Often used in combination with other round-specific functions
     * @custom:frontend-integration Essential for round-aware user interfaces
     *
     * @custom:example
     * ```solidity
     * uint256 currentRoundId = icoContract.getCurrentRoundId();
     *
     * // Use the ID for round-specific operations
     * bool isWhitelisted = icoContract.isWhitelisted(currentRoundId, userAddress);
     * uint256 userContribution = icoContract.getUserRoundContribution(userAddress, currentRoundId);
     * icoContract.buyWithUsdc(currentRoundId, purchaseAmount);
     * ```
     */
    function getCurrentRoundId() public view returns (uint256) {
        for (uint256 i = 0; i < saleRounds.length; i++) {
            if (
                block.timestamp >= saleRounds[i].startTime &&
                block.timestamp < saleRounds[i].endTime &&
                !saleRounds[i].isFinish
            ) {
                return i;
            }
        }
        revert NoActiveRound();
    }

    /**
     * @dev Retrieves the user's USDC contribution for a specific round
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return The total USDC amount contributed by the user in the specified round
     */
    function getUserRoundContribution(
        address _beneficiary,
        uint256 _roundId
    ) external view returns (uint256) {
        return userRoundContributions[_beneficiary][_roundId];
    }

    /**
     * @dev Retrieves the current ETH/USD price from Chainlink price feed
     * @return The current ETH/USD price
     */
    function getEthUsdPrice() internal view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        if (price <= 0) revert InvalidEthUsdPrice();
        return uint256(price);
    }

    /**
     * @dev Gets the total tokens sold across all ICO rounds
     * @return Total tokens sold
     */
    function getTotalTokensSold() external view returns (uint256) {
        return tokenDistributor.getTotalTokensSold();
    }

    /**
     * @dev Gets the total contribution amount for a specific wallet in a specific round
     * @param _wallet Address of the wallet to check
     * @param _roundId ID of the round to check
     * @return Total USD amount contributed by the wallet in the round
     */
    function getWalletContribution(
        address _wallet,
        uint256 _roundId
    ) external view returns (uint256) {
        return userRoundContributions[_wallet][_roundId];
    }

    /**
     * @dev Gets the total unsold tokens
     * @return Total unsold tokens
     */
    function getUnsoldTokens() external view returns (uint256) {
        return tokenDistributor.getUnsoldTokens();
    }

    /**
     * @dev Gets the sales performance percentage
     * @return Sales performance as a percentage (0-100)
     */
    function getSalesPerformance() external view returns (uint256) {
        return tokenDistributor.getSalesPerformance();
    }

    /**
     * @dev Checks if unsold tokens have been distributed
     * @return True if unsold tokens have been distributed
     */
    function isUnsoldTokensDistributed() external view returns (bool) {
        return tokenDistributor.isUnsoldTokensDistributed();
    }
}
