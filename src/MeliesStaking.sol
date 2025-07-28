// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./Melies.sol";

/**
 * @title MeliesStaking
 * @dev Manages the staking mechanism for Melies tokens.
 * Implements flexible staking options with different lock periods,
 * reward calculations based on staking duration, compound rewards,
 * and admin functions for staking management.
 */
contract MeliesStaking is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for Melies;

    /**
     * @dev Struct to store staking information for each user's stake
     */
    struct StakingInfo {
        uint256 amountWithPrecision;
        uint256 ponderatedAmountWithPrecision;
        uint256 accumulatedRewardsWithPrecision;
        uint32 startTime;
        uint32 endTime;
        uint32 lastClaimTime;
        uint8 durationIndex; // 0: no lock, 1: 30 days, 2: 90 days, 3: 180 days, 4: 365 days
        bool compoundRewards;
    }

    error RewardsBeingUpdated();
    error StakingAmountTooLow();
    error MinimumStakeRequired();
    error InvalidDurationIndex();
    error CannotStakeAfter90DaysFromTGE();
    error InvalidStakeIndex();
    error StakingPeriodNotEnded();
    error AmountGreaterThanStakeAmount();
    error AmountGreaterThanPonderatedStakeAmount();
    error NoRewardsToClaim();
    error CanOnlyUpdateOncePerDay();
    error CanOnlyToggleForNoLockStaking();
    error InvalidMultiplier();
    error DailyBudgetMustBeGreaterThanZero();
    error TgeTimestampAlreadySet();
    error TgeTimestampNotSet();
    error InvalidStartTime();

    Melies public meliesToken;

    uint256 private constant ANNUAL_BUDGET = 2_280_000e8; // 2.28M tokens
    uint256 public DAILY_BUDGET_TARGET =
        (ANNUAL_BUDGET / 365) * 10 ** PRECISION_FACTOR;
    uint256 private constant DURATION_MULTIPLIER_PRECISION = 2;
    uint256 private constant PRECISION_FACTOR = 12;
    uint256 private constant GAS_LIMIT_EXECUTION = 100_000;
    uint256 public MIN_STAKE_AMOUNT = 5000e8;
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint16[5] public DURATION_MULTIPLIERS = [1e2, 1.3e2, 1.6e2, 2.2e2, 3e2];

    uint256 private totalStakedWithPrecision;
    // Total ponderated staked is the total staked multiplied by the duration multiplier
    uint256 private totalPonderatedStakedWithPrecision;
    uint256 private savedTotalStaked;
    uint256 private savedTotalPonderatedStaked;
    uint256 private savedTotalRewards;
    mapping(address => StakingInfo[]) private userStakes;
    address[] private stakers;
    uint32 private tgeTimestamp;
    uint32 private lastUpdateTime;
    bool public tgeTimestampSet; // Track if TGE timestamp has been set
    uint32 private lastProcessedIndex;
    uint32 private lastProcessedStakeIndex;
    int64 private correctionDailyReward;
    bool public isRewardUpdating;

    event Staked(address indexed user, uint256 amount, uint8 durationIndex);
    event Unstaked(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EarlyUnstaked(
        address indexed user,
        uint256 amount,
        uint256 rewards,
        uint256 burnAmount,
        uint8 durationIndex,
        uint256 monthsElapsed
    );
    event TgeTimestampSet(uint256 tgeTimestamp);

    /**
     * @dev Constructor to initialize the MeliesStaking contract
     * @param _meliesToken Address of the Melies token contract
     */
    constructor(address _meliesToken) {
        meliesToken = Melies(_meliesToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Sets the TGE timestamp (one-time only, admin only)
     * @param _tgeTimestamp The TGE timestamp to set
     */
    function setTgeTimestamp(
        uint32 _tgeTimestamp
    ) external onlyRole(ADMIN_ROLE) {
        if (tgeTimestampSet) revert TgeTimestampAlreadySet();
        if (_tgeTimestamp == 0) revert InvalidStartTime();

        tgeTimestamp = _tgeTimestamp;
        tgeTimestampSet = true;

        emit TgeTimestampSet(_tgeTimestamp);
    }

    /**
     * @notice Stakes MEL tokens for a specified duration to earn rewards
     * @dev Stakes tokens with precision factor scaling and duration-based multipliers.
     * Creates a new StakingInfo entry with calculated ponderated amounts based on duration multipliers.
     * Uses 12-digit precision factor (10^12) for accurate reward calculations.
     *
     * Duration Options:
     * - Index 0: No lock, 1x multiplier, compound rewards optional
     * - Index 1: 90 days, 1.3x multiplier, auto-compound
     * - Index 2: 180 days, 1.6x multiplier, auto-compound
     * - Index 3: 365 days, 2.2x multiplier, auto-compound
     * - Index 4: 365 days VIP, 3x multiplier, auto-compound (min 200k MEL, 90-day window)
     *
     * Requirements:
     * - Contract must not be paused
     * - Rewards must not be currently updating
     * - Amount must be at least 5,000 MEL (MIN_STAKE_AMOUNT)
     * - Amount must be at least 200,000 MEL for VIP staking (index 4)
     * - Duration index must be valid (0-4)
     * - TGE timestamp must be set
     * - VIP staking (index 4) only available within 90 days of TGE
     * - User must have sufficient token balance and allowance
     *
     * @param _amount Amount of MEL tokens to stake (in wei, 8 decimals: 1 MEL = 1e8)
     * @param _durationIndex Staking duration index (0=no lock, 1=90d, 2=180d, 3=365d, 4=365d VIP)
     * @param _compoundRewards Whether to compound rewards (ignored for locked stakes, auto-true)
     *
     * @custom:security-note Uses SafeERC20 for token transfers and ReentrancyGuard protection
     * @custom:precision-note Amounts stored with 12-digit precision factor for accurate calculations
     * @custom:gas-note First stake for user adds them to stakers array (higher gas cost)
     *
     * Emits a {Staked} event with user address, amount, and duration index.
     */
    function stake(
        uint256 _amount,
        uint8 _durationIndex,
        bool _compoundRewards
    ) external whenNotPaused nonReentrant {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (_amount < MIN_STAKE_AMOUNT) revert StakingAmountTooLow();
        if (_durationIndex == 4 && _amount < 200000e8)
            revert StakingAmountTooLow();
        if (_durationIndex >= DURATION_MULTIPLIERS.length)
            revert InvalidDurationIndex();
        if (!tgeTimestampSet) revert TgeTimestampNotSet();
        if (_durationIndex == 4 && block.timestamp > tgeTimestamp + 90 days) {
            revert CannotStakeAfter90DaysFromTGE();
        }

        meliesToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 duration = getDurationFromIndex(_durationIndex);
        uint32 endTime = _durationIndex == 0
            ? 0
            : uint32(block.timestamp + duration);

        uint256 amountWithPrecision = _amount * 10 ** PRECISION_FACTOR;
        uint256 ponderatedAmountWithPrecision = _amount *
            DURATION_MULTIPLIERS[_durationIndex] *
            10 ** (PRECISION_FACTOR - DURATION_MULTIPLIER_PRECISION);

        userStakes[msg.sender].push(
            StakingInfo({
                amountWithPrecision: amountWithPrecision,
                ponderatedAmountWithPrecision: ponderatedAmountWithPrecision,
                startTime: uint32(block.timestamp),
                endTime: endTime,
                lastClaimTime: uint32(block.timestamp),
                accumulatedRewardsWithPrecision: 0,
                durationIndex: _durationIndex,
                compoundRewards: _durationIndex == 0 ? _compoundRewards : true
            })
        );

        totalStakedWithPrecision += amountWithPrecision;
        totalPonderatedStakedWithPrecision += ponderatedAmountWithPrecision;

        if (userStakes[msg.sender].length == 1) {
            stakers.push(msg.sender);
        }

        emit Staked(msg.sender, _amount, _durationIndex);
    }

    /**
     * @notice Unstakes MEL tokens and claims accumulated rewards after lock period ends
     * @dev Unstakes specified amount with precision factor handling and automatic reward distribution.
     * Converts ponderated amounts back to actual token amounts using duration multipliers.
     * Rewards are automatically included in the unstaked amount.
     *
     * Calculation Process:
     * 1. Validate staking period has ended (or no lock for index 0)
     * 2. Convert ponderated amount back to actual amount using multiplier
     * 3. Add accumulated rewards to principal amount
     * 4. Update global staking totals and user's stake
     * 5. Remove stake if fully unstaked or validate minimum requirements
     * 6. Transfer total amount (principal + rewards) to user
     *
     * Precision Handling:
     * - Input: ponderated amount with 12-digit precision (10^12)
     * - Conversion: ponderated ÷ duration_multiplier = actual amount
     * - Output: actual tokens transferred (8 decimals)
     *
     * Requirements:
     * - Contract must not be paused
     * - Rewards must not be currently updating
     * - Stake index must be valid
     * - Staking period must have ended (unless duration index 0)
     * - Unstake amount must not exceed ponderated stake amount
     * - Remaining stake (if partial) must meet minimum requirements
     * - If partial unstake leaves < 5,000 MEL, must unstake fully
     * - If partial unstake leaves VIP stake < 200,000 MEL, must unstake fully
     *
     * @param _stakeIndex Index of the user's stake to unstake (0-based array index)
     * @param _ponderatedAmountWithPrecision Ponderated amount to unstake (with 12-digit precision)
     *
     * @custom:security-note Uses ReentrancyGuard and SafeERC20 for secure token transfers
     * @custom:precision-note All calculations use 12-digit precision factor to prevent rounding errors
     * @custom:gas-note Removing last stake removes user from stakers array (gas refund)
     *
     * Emits an {Unstaked} event with user address, unstaked amount, and rewards claimed.
     *
     * @custom:example
     * ```solidity
     * // Get user's stake info to calculate ponderated amount
     * StakingInfo memory stake = getUserStakes(user)[0];
     *
     * // Unstake full amount after lock period
     * stakingContract.unstake(0, stake.ponderatedAmountWithPrecision);
     *
     * // Partial unstake (half the stake)
     * stakingContract.unstake(0, stake.ponderatedAmountWithPrecision / 2);
     * ```
     */
    function unstake(
        uint256 _stakeIndex,
        uint256 _ponderatedAmountWithPrecision
    ) public nonReentrant whenNotPaused {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (_stakeIndex >= userStakes[msg.sender].length)
            revert InvalidStakeIndex();
        StakingInfo storage userStake = userStakes[msg.sender][_stakeIndex];
        if (block.timestamp < userStake.endTime) revert StakingPeriodNotEnded();
        if (
            _ponderatedAmountWithPrecision >
            userStake.ponderatedAmountWithPrecision
        ) {
            revert AmountGreaterThanPonderatedStakeAmount();
        }

        uint256 rewardsWithPrecision = userStake
            .accumulatedRewardsWithPrecision;
        uint256 amountWithPrecision = (_ponderatedAmountWithPrecision *
            (10 ** DURATION_MULTIPLIER_PRECISION)) /
            DURATION_MULTIPLIERS[userStake.durationIndex];

        uint256 unstakeAmount = (amountWithPrecision + rewardsWithPrecision) /
            (10 ** PRECISION_FACTOR);

        if (userStake.amountWithPrecision < amountWithPrecision) {
            if (
                (amountWithPrecision - userStake.amountWithPrecision) <
                (10 ** PRECISION_FACTOR)
            ) {
                totalStakedWithPrecision -= userStake.amountWithPrecision;
                totalPonderatedStakedWithPrecision -= userStake
                    .ponderatedAmountWithPrecision;
                userStake.amountWithPrecision = 0;
                userStake.ponderatedAmountWithPrecision = 0;
            } else {
                revert AmountGreaterThanPonderatedStakeAmount();
            }
        } else {
            if (
                (userStake.amountWithPrecision - amountWithPrecision) <
                (10 ** PRECISION_FACTOR)
            ) {
                totalStakedWithPrecision -= userStake.amountWithPrecision;
                totalPonderatedStakedWithPrecision -= userStake
                    .ponderatedAmountWithPrecision;
                userStake.amountWithPrecision = 0;
                userStake.ponderatedAmountWithPrecision = 0;
            } else {
                totalStakedWithPrecision -= amountWithPrecision;
                totalPonderatedStakedWithPrecision -= _ponderatedAmountWithPrecision;
                userStake.amountWithPrecision -= amountWithPrecision;
                userStake
                    .ponderatedAmountWithPrecision -= _ponderatedAmountWithPrecision;
            }
        }
        userStake.accumulatedRewardsWithPrecision = 0;

        meliesToken.safeTransfer(msg.sender, unstakeAmount);

        if (
            userStake.amountWithPrecision == 0 ||
            userStake.ponderatedAmountWithPrecision == 0
        ) {
            userStake.amountWithPrecision = 0;
            userStake.ponderatedAmountWithPrecision = 0;

            // Remove the stake by swapping with the last element and popping
            userStakes[msg.sender][_stakeIndex] = userStakes[msg.sender][
                userStakes[msg.sender].length - 1
            ];
            userStakes[msg.sender].pop();
        } else {
            if (
                userStake.amountWithPrecision <
                MIN_STAKE_AMOUNT * 10 ** PRECISION_FACTOR
            ) revert MinimumStakeRequired();

            if (
                userStake.durationIndex == 4 &&
                userStake.amountWithPrecision <
                200000e8 * 10 ** PRECISION_FACTOR
            ) revert MinimumStakeRequired();
        }

        emit Unstaked(
            msg.sender,
            amountWithPrecision / 10 ** PRECISION_FACTOR,
            rewardsWithPrecision / 10 ** PRECISION_FACTOR
        );
    }

    /**
     * @notice Unstakes MEL tokens before lock period ends with progressive burn penalty
     * @dev Allows early unstaking with burn penalties that decrease over time to incentivize longer staking.
     * Burns a percentage of total amount (principal + rewards) as penalty.
     * Automatically calls normal unstake() if lock period has ended or for no-lock stakes.
     *
     * Burn Penalty Schedule by Duration Index:
     * - Index 1 (90 days): 60% → 0% (linear decrease over 90 days)
     * - Index 2 (180 days): 80% → 0% (linear decrease over 180 days)
     * - Index 3 (365 days): 90% → 0% (linear decrease over 365 days)
     * - Index 4 (365 days VIP): 95% → 0% (linear decrease over 365 days)
     *
     * Process:
     * 1. Check if early unstaking is applicable (locked and before end time)
     * 2. Calculate months elapsed since staking start
     * 3. Determine burn percentage based on program and elapsed time
     * 4. Calculate total amount (principal + rewards)
     * 5. Apply burn penalty to total amount
     * 6. Mint penalty tokens to contract, then burn them (for tracking)
     * 7. Transfer net amount to user after penalty
     * 8. Update stake balances or remove if fully unstaked
     *
     * Requirements:
     * - Contract must not be paused
     * - Rewards must not be currently updating
     * - Stake index must be valid
     * - Must be a locked stake (duration index > 0) and before lock period ends
     * - Unstake amount must not exceed ponderated stake amount
     * - Remaining stake must meet minimum requirements if partial unstake
     *
     * @param _stakeIndex Index of the user's stake to unstake early (0-based array index)
     * @param _ponderatedAmountWithPrecision Ponderated amount to unstake (with 12-digit precision)
     *
     * @custom:security-note Burn mechanism prevents gaming of staking rewards and maintains tokenomics
     * @custom:precision-note Uses precise burn percentage calculations to avoid rounding exploits
     * @custom:gas-note Burns tokens by minting then burning to maintain accurate totalSupply tracking
     *
     * Emits an {EarlyUnstaked} event with user, amount, rewards, burn amount, duration index, and months elapsed.
     *
     * @custom:example
     * ```solidity
     * // Early unstake after 1 month of 90-day stake (high ~40% burn penalty)
     * stakingContract.earlyUnstake(0, stake.ponderatedAmountWithPrecision);
     *
     * // Early unstake after 80 days of 90-day stake (low ~7% burn penalty)
     * stakingContract.earlyUnstake(0, stake.ponderatedAmountWithPrecision);
     * ```
     */
    function earlyUnstake(
        uint256 _stakeIndex,
        uint256 _ponderatedAmountWithPrecision
    ) external nonReentrant whenNotPaused {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (_stakeIndex >= userStakes[msg.sender].length)
            revert InvalidStakeIndex();

        StakingInfo storage userStake = userStakes[msg.sender][_stakeIndex];

        // If there is no lock or the staking period has ended, unstake normally
        if (
            userStake.durationIndex == 0 || block.timestamp >= userStake.endTime
        ) {
            unstake(_stakeIndex, _ponderatedAmountWithPrecision);
            return;
        }

        if (
            _ponderatedAmountWithPrecision >
            userStake.ponderatedAmountWithPrecision
        ) {
            revert AmountGreaterThanPonderatedStakeAmount();
        }

        // Calculate elapsed months and burn percentage
        uint256 monthsElapsed = calculateElapsedMonths(userStake.startTime);
        uint256 burnPercentage = calculateEarlyUnstakingBurnPercentage(
            userStake.durationIndex,
            monthsElapsed
        );

        uint256 rewardsWithPrecision = userStake
            .accumulatedRewardsWithPrecision;
        uint256 amountWithPrecision = (_ponderatedAmountWithPrecision *
            (10 ** DURATION_MULTIPLIER_PRECISION)) /
            DURATION_MULTIPLIERS[userStake.durationIndex];

        // Calculate total amount (principal + rewards)
        uint256 totalAmountWithPrecision = amountWithPrecision +
            rewardsWithPrecision;

        // Calculate burn amount
        uint256 burnAmountWithPrecision = (totalAmountWithPrecision *
            burnPercentage) / 10000;
        uint256 netAmountWithPrecision = totalAmountWithPrecision -
            burnAmountWithPrecision;

        // Update stake balances
        if (userStake.amountWithPrecision < amountWithPrecision) {
            if (
                (amountWithPrecision - userStake.amountWithPrecision) <
                (10 ** PRECISION_FACTOR)
            ) {
                totalStakedWithPrecision -= userStake.amountWithPrecision;
                totalPonderatedStakedWithPrecision -= userStake
                    .ponderatedAmountWithPrecision;
                userStake.amountWithPrecision = 0;
                userStake.ponderatedAmountWithPrecision = 0;
            } else {
                revert AmountGreaterThanPonderatedStakeAmount();
            }
        } else {
            if (
                (userStake.amountWithPrecision - amountWithPrecision) <
                (10 ** PRECISION_FACTOR)
            ) {
                totalStakedWithPrecision -= userStake.amountWithPrecision;
                totalPonderatedStakedWithPrecision -= userStake
                    .ponderatedAmountWithPrecision;
                userStake.amountWithPrecision = 0;
                userStake.ponderatedAmountWithPrecision = 0;
            } else {
                totalStakedWithPrecision -= amountWithPrecision;
                totalPonderatedStakedWithPrecision -= _ponderatedAmountWithPrecision;
                userStake.amountWithPrecision -= amountWithPrecision;
                userStake
                    .ponderatedAmountWithPrecision -= _ponderatedAmountWithPrecision;
            }
        }
        userStake.accumulatedRewardsWithPrecision = 0;

        // Transfer net amount to user
        uint256 netUnstakeAmount = netAmountWithPrecision /
            (10 ** PRECISION_FACTOR);
        uint256 burnAmount = burnAmountWithPrecision / (10 ** PRECISION_FACTOR);

        meliesToken.safeTransfer(msg.sender, netUnstakeAmount);

        // Burn the penalty amount
        if (burnAmount > 0) {
            meliesToken.burn(address(this), burnAmount);
        }

        // Remove stake if fully unstaked
        if (
            userStake.amountWithPrecision == 0 ||
            userStake.ponderatedAmountWithPrecision == 0
        ) {
            userStake.amountWithPrecision = 0;
            userStake.ponderatedAmountWithPrecision = 0;

            // Remove the stake by swapping with the last element and popping
            userStakes[msg.sender][_stakeIndex] = userStakes[msg.sender][
                userStakes[msg.sender].length - 1
            ];
            userStakes[msg.sender].pop();
        } else {
            // Check minimum stake requirements for remaining amount
            if (
                userStake.amountWithPrecision <
                MIN_STAKE_AMOUNT * 10 ** PRECISION_FACTOR
            ) revert MinimumStakeRequired();

            if (
                userStake.durationIndex == 4 &&
                userStake.amountWithPrecision <
                200000e8 * 10 ** PRECISION_FACTOR
            ) revert MinimumStakeRequired();
        }

        emit EarlyUnstaked(
            msg.sender,
            amountWithPrecision / 10 ** PRECISION_FACTOR,
            rewardsWithPrecision / 10 ** PRECISION_FACTOR,
            burnAmount,
            userStake.durationIndex,
            monthsElapsed
        );
    }

    /**
     * @dev Internal function to get the duration in seconds from the duration index
     * @param durationIndex Index representing the staking duration
     * @return Duration in seconds
     */
    function getDurationFromIndex(
        uint8 durationIndex
    ) internal pure returns (uint32) {
        if (durationIndex == 0) return 0; // No lock
        if (durationIndex == 1) return 90 days;
        if (durationIndex == 2) return 180 days;
        if (durationIndex == 3 || durationIndex == 4) return 365 days;
        revert InvalidDurationIndex();
    }

    /**
     * @dev Internal function to calculate burn percentage for early unstaking
     * @param durationIndex Index representing the staking duration
     * @param monthsElapsed Number of full months that have elapsed since staking
     * @return burnPercentage Percentage to burn (0-9000 representing 0-90%)
     */
    function calculateEarlyUnstakingBurnPercentage(
        uint8 durationIndex,
        uint256 monthsElapsed
    ) internal pure returns (uint256 burnPercentage) {
        // No burn for no-lock staking (index 0)
        if (durationIndex == 0) return 0;

        // index 1 (3 months lock-up)
        if (durationIndex == 1) {
            if (monthsElapsed == 0) return 9000; // 90%
            if (monthsElapsed == 1) return 6000; // 60%
            if (monthsElapsed == 2) return 3000; // 30%
            return 0; // After 3 months, no burn
        }

        // index 2 (6 months lock-up)
        if (durationIndex == 2) {
            if (monthsElapsed == 0) return 9000; // 90%
            if (monthsElapsed == 1) return 7500; // 75%
            if (monthsElapsed == 2) return 6000; // 60%
            if (monthsElapsed == 3) return 4500; // 45%
            if (monthsElapsed == 4) return 3000; // 30%
            if (monthsElapsed == 5) return 1500; // 15%
            return 0; // After 6 months, no burn
        }

        // index 3 & 4 (12 months lock-up)
        if (durationIndex == 3 || durationIndex == 4) {
            if (monthsElapsed == 0) return 9000; // 90.0%
            if (monthsElapsed == 1) return 8250; // 82.5%
            if (monthsElapsed == 2) return 7500; // 75.0%
            if (monthsElapsed == 3) return 6750; // 67.5%
            if (monthsElapsed == 4) return 6000; // 60.0%
            if (monthsElapsed == 5) return 5250; // 52.5%
            if (monthsElapsed == 6) return 4500; // 45.0%
            if (monthsElapsed == 7) return 3750; // 37.5%
            if (monthsElapsed == 8) return 3000; // 30.0%
            if (monthsElapsed == 9) return 2250; // 22.5%
            if (monthsElapsed == 10) return 1500; // 15.0%
            if (monthsElapsed == 11) return 750; // 7.5%
            return 0; // After 12 months, no burn
        }

        revert InvalidDurationIndex();
    }

    /**
     * @dev Internal function to calculate elapsed months since staking start
     * @param startTime The timestamp when staking started
     * @return monthsElapsed Number of full months elapsed
     */
    function calculateElapsedMonths(
        uint32 startTime
    ) internal view returns (uint256 monthsElapsed) {
        if (block.timestamp <= startTime) return 0;

        uint256 secondsElapsed = block.timestamp - startTime;
        // Calculate months as 30-day periods for simplicity
        uint256 daysElapsed = secondsElapsed / 1 days;
        monthsElapsed = daysElapsed / 30;

        return monthsElapsed;
    }

    /**
     * @dev Allows users to claim their accumulated rewards
     * @param stakeIndex Index of the stake to claim rewards from
     */
    function claimRewards(
        uint256 stakeIndex
    ) external nonReentrant whenNotPaused {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (stakeIndex >= userStakes[msg.sender].length)
            revert InvalidStakeIndex();
        StakingInfo storage userStake = userStakes[msg.sender][stakeIndex];

        uint256 rewardsWithPrecision = userStake
            .accumulatedRewardsWithPrecision;
        if (rewardsWithPrecision == 0) revert NoRewardsToClaim();

        userStake.lastClaimTime = uint32(block.timestamp);
        userStake.accumulatedRewardsWithPrecision = 0;

        meliesToken.safeTransfer(
            msg.sender,
            rewardsWithPrecision / 10 ** PRECISION_FACTOR
        );

        emit RewardsClaimed(
            msg.sender,
            rewardsWithPrecision / 10 ** PRECISION_FACTOR
        );
    }

    /**
     * @dev Calculates the rewards for a specific stake
     * @param user Address of the user
     * @param stakeIndex Index of the stake
     * @param dailyBudget Daily budget for rewards
     * @return Rewards and ponderated rewards with precision
     */
    function calculateRewards(
        address user,
        uint256 stakeIndex,
        uint256 dailyBudget
    ) public view returns (uint256, uint256) {
        StakingInfo storage userStake = userStakes[user][stakeIndex];

        // Rewards calculation is based on the ratio of ponderated staked amount over total ponderated staked amount multiplied by daily budget

        // Start with numerator
        uint256 rewardsNumerator = userStake.ponderatedAmountWithPrecision *
            dailyBudget;

        // Then divide by total ponderated staked amount
        uint256 rewardsWithPrecision = rewardsNumerator /
            totalPonderatedStakedWithPrecision;

        // For ponderated rewards, we need to multiply by the duration multiplier on top of the division by total ponderated staked amount
        uint256 ponderatedRewardsWithPrecision = (rewardsNumerator *
            DURATION_MULTIPLIERS[userStake.durationIndex]) /
            10 ** DURATION_MULTIPLIER_PRECISION /
            totalPonderatedStakedWithPrecision;

        // NOTE : dailyBudget has precision aswell, so results still have precision factor
        // (amountWithPrecision * dailyBudgetWithPrecision / totalPonderatedStakedWithPrecision -> P² / P)
        return (rewardsWithPrecision, ponderatedRewardsWithPrecision);
    }

    /**
     * @notice Updates the global accumulated rewards pool for all stakers based on daily budget allocation
     * @dev Critical daily maintenance function that distributes rewards proportionally to all stakers.
     * Uses precision-based calculations and gap correction mechanisms to ensure fair reward distribution.
     * Can be suspended during updates to prevent calculation conflicts.
     *
     * Daily Reward Distribution Process:
     * 1. Validate 24-hour cooldown period (with 1-minute tolerance for blockchain timing)
     * 2. Retrieve saved state from any previous incomplete updates
     * 3. Apply gap correction from previous day's actual vs target distribution
     * 4. Calculate proportional rewards based on ponderated staking amounts
     * 5. Update global accumulated reward trackers
     * 6. Apply precision factor scaling (10^12) for accurate micro-rewards
     *
     * Gap Correction System:
     * - If yesterday's rewards exceeded target: reduce today's budget
     * - If yesterday's rewards were below target: increase today's budget
     * - Helps maintain consistent daily reward output over time
     *
     * Security Design - No Role Required:
     * This function is designed to be callable by anyone without access control because:
     * - Built-in 24-hour cooldown prevents spam calls (CanOnlyUpdateOncePerDay)
     * - State lock (isRewardUpdating) prevents concurrent execution conflicts
     * - Only distributes rewards proportionally - cannot drain funds or manipulate balances
     * - All calculations are deterministic based on current staking state
     * - No parameters can be manipulated to alter reward distribution
     * - Function benefits the protocol and stakers - no incentive for malicious use
     * - Allows automated systems and community members to maintain rewards without privileged access
     *
     * Requirements:
     * - Must wait at least 23 hours 59 minutes since last update
     * - Reward updating flag must not be active (prevents concurrent updates)
     * - TGE timestamp must be set (staking rewards start after TGE)
     *
     * @custom:security-note This function temporarily locks reward updates to prevent state corruption
     * @custom:gas-optimization Uses saved state to resume interrupted updates efficiently
     *
     * Emits multiple events depending on the update outcome:
     * - Updates global accumulatedRewardsWithPrecision values
     * - Modifies correctionDailyReward for next day's gap correction
     *
     * @custom:example
     * ```solidity
     * // Can be called daily by anyone - admin, automated system, or community member
     * stakingContract.updateAccumulatedRewards();
     * ```
     */
    function updateAccumulatedRewards() external {
        // wait for 1 days since last update
        if (block.timestamp < lastUpdateTime + 1 days)
            revert CanOnlyUpdateOncePerDay();

        isRewardUpdating = true;

        // retreive values from previous update (if last update was unfinished, else 0)
        uint256 addToTotalPonderatedStaked = savedTotalPonderatedStaked;
        uint256 addToTotalStaked = savedTotalStaked;
        uint256 totalRewards = savedTotalRewards;

        uint256 ajustedDailyRewards = 0;
        // adjust daily rewards based on previous gap
        if (correctionDailyReward > 0) {
            ajustedDailyRewards =
                DAILY_BUDGET_TARGET -
                uint256(int256(correctionDailyReward));
        } else {
            ajustedDailyRewards =
                DAILY_BUDGET_TARGET +
                uint256(int256(-correctionDailyReward));
        }

        // initialize index to last processed index (if last update was unfinished, else 0)
        uint32 i = lastProcessedIndex;
        uint32 j = lastProcessedStakeIndex;
        uint256 totalCompoundRewardsWithPrecision;

        // Update rewards for stakers until we run out of gas or process all stakers
        while (i < stakers.length && gasleft() > GAS_LIMIT_EXECUTION) {
            address user = stakers[i];
            totalCompoundRewardsWithPrecision = 0;
            if (userStakes[user].length == 0) {
                // Remove user from stakers array if they have no stakes
                stakers[i] = stakers[stakers.length - 1];
                stakers.pop();
            } else {
                // Update rewards for all stakes of the current user
                while (
                    j < userStakes[user].length &&
                    gasleft() > GAS_LIMIT_EXECUTION
                ) {
                    StakingInfo storage userStake = userStakes[user][j];

                    // Calculate rewards for the current stake
                    (
                        uint256 rewardsWithPrecision,
                        uint256 ponderatedRewardsWithPrecision
                    ) = calculateRewards(user, j, ajustedDailyRewards);

                    // Add rewards to total rewards
                    totalRewards += rewardsWithPrecision;

                    // If compound rewards is enabled, add rewards to the stake and update total ponderated staked
                    if (userStake.compoundRewards) {
                        // Add rewards to the stake and update total ponderated staked
                        userStake.amountWithPrecision += rewardsWithPrecision;
                        userStake
                            .ponderatedAmountWithPrecision += ponderatedRewardsWithPrecision;
                        addToTotalStaked += rewardsWithPrecision;
                        addToTotalPonderatedStaked += ponderatedRewardsWithPrecision;
                        totalCompoundRewardsWithPrecision += rewardsWithPrecision;
                    } else {
                        // Add rewards to the stake reward
                        userStake
                            .accumulatedRewardsWithPrecision += rewardsWithPrecision;
                    }

                    // Update last claim time
                    userStake.lastClaimTime = uint32(block.timestamp);
                    j++;
                }

                // Reset stake index and increment user index if we reached the end of the staking array
                // not triggered if gas is missing and we need to continue on next call
                if (j >= userStakes[user].length) {
                    j = 0;
                    i++;
                }
            }
        }

        // if we processed all stakers, update is done
        if (i == stakers.length) {
            // Update total ponderated staked and total staked
            totalPonderatedStakedWithPrecision += addToTotalPonderatedStaked;
            totalStakedWithPrecision += addToTotalStaked;

            // reset values for next update
            lastProcessedIndex = 0;
            lastProcessedStakeIndex = 0;
            savedTotalStaked = 0;
            savedTotalPonderatedStaked = 0;
            savedTotalRewards = 0;

            // update last update time
            if (lastUpdateTime == 0) {
                lastUpdateTime = uint32(block.timestamp);
            } else {
                lastUpdateTime = lastUpdateTime + 1 days;
            }

            // if total rewards is not 0, we need to adjust the daily budget
            if (totalRewards > 0) {
                correctionDailyReward = int64(
                    int256(totalRewards) - int256(ajustedDailyRewards)
                );
            }

            // update is done
            isRewardUpdating = false;
        } else {
            // update temporary values for next call
            lastProcessedIndex = i;
            lastProcessedStakeIndex = j;
            savedTotalStaked = addToTotalStaked;
            savedTotalPonderatedStaked = addToTotalPonderatedStaked;
            savedTotalRewards = totalRewards;
        }
    }

    /**
     * @notice Toggles automatic reward compounding on/off for a specific no-lock stake
     * @dev Allows users to change their reward compounding preference for flexible (index 0) stakes only.
     * Locked stakes (index 1-4) have fixed compounding enabled and cannot be changed.
     * Compounding automatically reinvests claimed rewards into the same stake to increase future rewards.
     *
     * Compounding Mechanics:
     * - When enabled: rewards are automatically added to stake principal
     * - When disabled: rewards must be manually claimed via claimRewards()
     * - Only affects future reward distribution, not past accumulated rewards
     * - Toggle can be changed multiple times without penalties
     *
     * Requirements:
     * - Stake must exist (valid stakeIndex for the caller)
     * - Only works for no-lock staking (durationIndex 0)
     * - Locked duration stakes always have compounding enabled
     *
     * @param stakeIndex The index of the user's stake to modify compounding setting
     *
     * @custom:security-note Non-reentrant to prevent manipulation during reward calculations
     *
     * State Changes:
     * - Flips the compoundRewards boolean for the specified stake
     * - Does not affect the stake amount or accumulated rewards
     *
     * @custom:example
     * ```solidity
     * // Enable compounding for stake #0
     * stakingContract.toggleCompoundRewards(0);
     * // Disable compounding for the same stake
     * stakingContract.toggleCompoundRewards(0);
     * ```
     */
    function toggleCompoundRewards(uint256 stakeIndex) external nonReentrant {
        if (stakeIndex >= userStakes[msg.sender].length)
            revert InvalidStakeIndex();
        StakingInfo storage userStake = userStakes[msg.sender][stakeIndex];
        if (userStake.durationIndex != 0)
            revert CanOnlyToggleForNoLockStaking();

        userStake.compoundRewards = !userStake.compoundRewards;
    }

    /**
     * @notice Returns the total amount of MEL tokens currently staked across all users and duration programs
     * @dev Aggregates staking amounts from all users and duration indexes, converted from precision-scaled storage.
     * Provides real-time view of total capital locked in the staking system for analytics and monitoring.
     *
     * Calculation Process:
     * - Retrieves totalStakedWithPrecision from internal storage
     * - Divides by PRECISION_FACTOR (10^12) to convert back to token units
     * - Returns human-readable token amount with 8 decimal places
     *
     * Data Sources:
     * - Includes stakes from all duration programs (index 0-4)
     * - Includes both locked and unlocked stakes
     * - Includes principal amounts only (excludes compounded rewards)
     * - Updated in real-time with each stake/unstake operation
     *
     * Use Cases:
     * - Protocol analytics and TVL calculations
     * - Reward distribution percentage calculations
     * - Security monitoring for stake concentration
     * - Front-end display of total staking activity
     *
     * @return The total amount of staked MEL tokens (8 decimals)
     *
     * @custom:view-function Pure read operation with no state changes
     * @custom:gas-optimization Simple arithmetic operation, very low gas cost
     *
     * @custom:example
     * ```solidity
     * uint256 totalStaked = stakingContract.getTotalStaked();
     * // Returns: 50000000000000 (representing 500,000.00000000 MEL tokens)
     * ```
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStakedWithPrecision / 10 ** PRECISION_FACTOR;
    }

    /**
     * @notice Returns the total ponderated (weighted) staking amount used for proportional reward calculations
     * @dev Aggregates duration-adjusted staking amounts across all users, showing total weighted influence.
     * Critical for understanding reward distribution proportions and staking program effectiveness.
     * Higher values indicate longer-duration stakes which receive proportionally more rewards.
     *
     * Ponderation System:
     * - Index 0 (no lock): 1.0x multiplier (100% weight)
     * - Index 1 (90 days): 1.3x multiplier (130% weight)
     * - Index 2 (180 days): 1.6x multiplier (160% weight)
     * - Index 3 (365 days): 2.2x multiplier (220% weight)
     * - Index 4 (365 days VIP): 3.0x multiplier (300% weight)
     *
     * Calculation Process:
     * - Each stake is multiplied by its duration multiplier
     * - All ponderated amounts are summed across users and programs
     * - Stored with PRECISION_FACTOR (10^12) for micro-reward accuracy
     * - Converted back to readable format for external consumption
     *
     * Reward Distribution Usage:
     * - User's reward share = (user ponderated amount) / (total ponderated amount)
     * - Incentivizes longer staking commitments with higher reward weights
     * - Used by updateAccumulatedRewards() for daily reward allocation
     *
     * @return The total ponderated staking amount (duration-weighted, 8 decimals)
     *
     * @custom:view-function Pure read operation with no state changes
     * @custom:reward-critical Essential for accurate reward distribution calculations
     *
     * @custom:example
     * ```solidity
     * uint256 totalPonderated = stakingContract.getTotalPonderatedStaked();
     * // If total regular stakes = 100M MEL, total ponderated might be 180M MEL
     * // (indicating average ~1.8x multiplier from longer duration preferences)
     * ```
     */
    function getTotalPonderatedStaked() external view returns (uint256) {
        return totalPonderatedStakedWithPrecision / 10 ** PRECISION_FACTOR;
    }

    /**
     * @notice Retrieves complete staking portfolio information for a specific user address
     * @dev Returns comprehensive array of all StakingInfo structs associated with the user.
     * Essential for frontend applications, portfolio analytics, and user account management.
     * Provides complete visibility into user's staking positions across all duration programs.
     *
     * StakingInfo Struct Contents (per stake):
     * - amountWithPrecision: Staked amount scaled by PRECISION_FACTOR (10^12)
     * - ponderatedAmountWithPrecision: Duration-weighted amount for reward calculations
     * - stakingTimestamp: Unix timestamp when stake was created
     * - durationIndex: Duration program (0=no lock, 1=90d, 2=180d, 3=365d, 4=365d VIP)
     * - compoundRewards: Whether rewards are automatically reinvested
     * - accumulatedRewardsWithPrecision: Precision-scaled accumulated rewards
     *
     * Data Processing Recommendations:
     * - Divide amounts by PRECISION_FACTOR (10^12) for human-readable values
     * - Use durationIndex to determine lock status and multiplier
     * - Check stakingTimestamp + duration to calculate unlock times
     * - Sum amountWithPrecision across stakes for total user staking
     *
     * Common Use Cases:
     * - Portfolio dashboard displaying all user positions
     * - Calculating total staked amounts and pending rewards
     * - Determining which stakes are unlocked and withdrawable
     * - Historical analysis of staking behavior and strategy
     * - Tax reporting and accounting for staking activities
     *
     * @param user The wallet address to retrieve staking information for
     *
     * @return Array of StakingInfo structs containing complete staking portfolio data
     *
     * @custom:view-function Pure read operation with no gas cost when called externally
     * @custom:frontend-critical Essential function for user interface and portfolio management
     * @custom:array-return May return large arrays for heavy stakers - consider pagination in UI
     *
     * @custom:example
     * ```solidity
     * StakingInfo[] memory stakes = stakingContract.getUserStakes(userAddress);
     *
     * for (uint i = 0; i < stakes.length; i++) {
     *     uint256 amount = stakes[i].amountWithPrecision / 10**12;
     *     uint8 duration = stakes[i].durationIndex;
     *     bool isLocked = (block.timestamp < stakes[i].stakingTimestamp + DURATION_DAYS[duration] * 1 days);
     *     // Process each stake for display or calculations
     * }
     * ```
     */
    function getUserStakes(
        address user
    ) external view returns (StakingInfo[] memory) {
        return userStakes[user];
    }

    /**
     * @dev Returns the total amount of stakes for a specific user
     * @param user Address of the user
     * @return totalStakes Total amount of stakes for the user
     */
    function getTotalUserStakes(
        address user
    ) external view returns (uint256 totalStakes) {
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            totalStakes += userStakes[user][i].amountWithPrecision;
        }
        totalStakes /= 10 ** PRECISION_FACTOR;
    }

    /**
     * @dev Pauses the contract
     * Can only be called by admin
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     * Can only be called by admin
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Allows admin to withdraw tokens in case of emergency
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Allows admin to change the DURATION_MULTIPLIERS
     * @param newMultipliers New array of duration multipliers
     */
    function setDurationMultipliers(
        uint16[5] memory newMultipliers
    ) external onlyRole(ADMIN_ROLE) {
        if (newMultipliers[0] != 1e2) revert InvalidMultiplier();
        for (uint8 i = 1; i < 5; i++) {
            if (newMultipliers[i] <= newMultipliers[i - 1])
                revert InvalidMultiplier();
            if (newMultipliers[i] > 10000) revert InvalidMultiplier();
        }
        DURATION_MULTIPLIERS = newMultipliers;
    }

    /**
     * @dev Allows admin to change the DAILY_BUDGET_TARGET
     * @param newDailyBudget New daily budget target
     */
    function setDailyBudgetTarget(
        uint256 newDailyBudget
    ) external onlyRole(ADMIN_ROLE) {
        if (newDailyBudget == 0) revert DailyBudgetMustBeGreaterThanZero();
        DAILY_BUDGET_TARGET = newDailyBudget * 10 ** PRECISION_FACTOR;
    }

    /**
     * @dev Allows admin to change the MIN_STAKE_AMOUNT
     * @param newMinStakeAmount New minimum stake amount
     */
    function setMinStakeAmount(
        uint256 newMinStakeAmount
    ) external onlyRole(ADMIN_ROLE) {
        MIN_STAKE_AMOUNT = newMinStakeAmount;
    }

    /**
     * @dev Checks if TGE timestamp has been set
     * @return True if TGE timestamp has been set
     */
    function isTgeTimestampSet() external view returns (bool) {
        return tgeTimestampSet;
    }

    // View functions for early unstaking information

    /**
     * @dev Calculates the burn percentage for early unstaking preview
     * @param durationIndex Index representing the staking duration
     * @param monthsElapsed Number of full months elapsed since staking
     * @return burnPercentage Percentage to burn (0-9000 representing 0-90%)
     */
    function getEarlyUnstakingBurnPercentage(
        uint8 durationIndex,
        uint256 monthsElapsed
    ) external pure returns (uint256 burnPercentage) {
        return
            calculateEarlyUnstakingBurnPercentage(durationIndex, monthsElapsed);
    }

    /**
     * @dev Previews the early unstaking result for a user's stake
     * @param user Address of the user
     * @param stakeIndex Index of the stake
     * @param ponderatedAmountWithPrecision Amount to unstake with precision
     * @return netAmount Amount user would receive after burn
     * @return burnAmount Amount that would be burned
     * @return burnPercentage Burn percentage applied (0-9000)
     * @return monthsElapsed Number of months elapsed since staking
     */
    function previewEarlyUnstaking(
        address user,
        uint256 stakeIndex,
        uint256 ponderatedAmountWithPrecision
    )
        external
        view
        returns (
            uint256 netAmount,
            uint256 burnAmount,
            uint256 burnPercentage,
            uint256 monthsElapsed
        )
    {
        require(stakeIndex < userStakes[user].length, "Invalid stake index");
        StakingInfo storage userStake = userStakes[user][stakeIndex];

        // Calculate elapsed months and burn percentage
        monthsElapsed = calculateElapsedMonths(userStake.startTime);
        burnPercentage = calculateEarlyUnstakingBurnPercentage(
            userStake.durationIndex,
            monthsElapsed
        );

        uint256 rewardsWithPrecision = userStake
            .accumulatedRewardsWithPrecision;
        uint256 amountWithPrecision = (ponderatedAmountWithPrecision *
            (10 ** DURATION_MULTIPLIER_PRECISION)) /
            DURATION_MULTIPLIERS[userStake.durationIndex];

        // Calculate total amount (principal + rewards)
        uint256 totalAmountWithPrecision = amountWithPrecision +
            rewardsWithPrecision;

        // Calculate burn amount
        uint256 burnAmountWithPrecision = (totalAmountWithPrecision *
            burnPercentage) / 10000;
        uint256 netAmountWithPrecision = totalAmountWithPrecision -
            burnAmountWithPrecision;

        netAmount = netAmountWithPrecision / (10 ** PRECISION_FACTOR);
        burnAmount = burnAmountWithPrecision / (10 ** PRECISION_FACTOR);
    }
}
