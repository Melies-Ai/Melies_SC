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
    error Minimum5000MELStakeRequired();
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
    error EarlyUnstakingNotAllowed();
    error CannotEarlyUnstakeNoLockStaking();

    Melies public meliesToken;

    uint256 private constant ANNUAL_BUDGET = 2_280_000e8; // 2.28M tokens
    uint256 public DAILY_BUDGET_TARGET =
        (ANNUAL_BUDGET / 365) * 10 ** PRECISION_FACTOR;
    uint256 private constant DURATION_MULTIPLIER_PRECISION = 2;
    uint256 private constant PRECISION_FACTOR = 12;
    uint256 private constant GAS_LIMIT_EXECUTION = 100_000;
    uint256 public MIN_STAKE_AMOUNT = 150e8;
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

    /**
     * @dev Constructor to initialize the MeliesStaking contract
     * @param _meliesToken Address of the Melies token contract
     * @param _tgeTimestamp Timestamp for the Token Generation Event (TGE)
     */
    constructor(address _meliesToken, uint32 _tgeTimestamp) {
        meliesToken = Melies(_meliesToken);
        tgeTimestamp = _tgeTimestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Grants BURNER_ROLE to this contract for early unstaking burns
     * Must be called by an admin after deployment
     */
    function initializeBurnerRole() external onlyRole(ADMIN_ROLE) {
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), address(this));
    }

    /**
     * @dev Allows users to stake their tokens
     * @param _amount Amount of tokens to stake (minimum 150 MEL, 5000 MEL for index 4)
     * @param _durationIndex Index representing the staking duration
     * @param _compoundRewards Whether to compound rewards or not
     * Requirements:
     * - Amount must be at least 150 MEL tokens for all stakes
     * - Amount must be at least 5000 MEL tokens for index 4 stakes
     * - Cannot stake with index 4 after 90 days from TGE
     */
    function stake(
        uint256 _amount,
        uint8 _durationIndex,
        bool _compoundRewards
    ) external whenNotPaused nonReentrant {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (_amount < MIN_STAKE_AMOUNT) revert StakingAmountTooLow();
        if (_durationIndex == 4 && _amount < 5000e8)
            revert Minimum5000MELStakeRequired();
        if (_durationIndex >= DURATION_MULTIPLIERS.length)
            revert InvalidDurationIndex();
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
     * @dev Allows users to unstake their tokens and claim rewards
     * @param _stakeIndex Index of the stake to unstake
     * @param _ponderatedAmountWithPrecision Amount to unstake with precision
     * Requirements:
     * - Remaining amount must be at least 150 MEL tokens for all stakes
     * - Remaining amount must be at least 5000 MEL tokens for index 4 stakes
     * - Staking period must have ended
     */
    function unstake(
        uint256 _stakeIndex,
        uint256 _ponderatedAmountWithPrecision
    ) external nonReentrant {
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
            ) revert StakingAmountTooLow();

            if (
                userStake.durationIndex == 4 &&
                userStake.amountWithPrecision < 5000e8 * 10 ** PRECISION_FACTOR
            ) revert Minimum5000MELStakeRequired();
        }

        emit Unstaked(
            msg.sender,
            amountWithPrecision / 10 ** PRECISION_FACTOR,
            rewardsWithPrecision / 10 ** PRECISION_FACTOR
        );
    }

    /**
     * @dev Allows users to unstake their tokens early with burn penalty
     * @param _stakeIndex Index of the stake to unstake
     * @param _ponderatedAmountWithPrecision Amount to unstake with precision
     * Requirements:
     * - Cannot be used for no-lock staking (index 0)
     * - Must be before the lock period ends
     * - Burn percentage is applied based on staking program and elapsed time
     */
    function earlyUnstake(
        uint256 _stakeIndex,
        uint256 _ponderatedAmountWithPrecision
    ) external nonReentrant {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (_stakeIndex >= userStakes[msg.sender].length)
            revert InvalidStakeIndex();

        StakingInfo storage userStake = userStakes[msg.sender][_stakeIndex];

        // Cannot early unstake no-lock staking
        if (userStake.durationIndex == 0)
            revert CannotEarlyUnstakeNoLockStaking();

        // Must be before the lock period ends
        if (block.timestamp >= userStake.endTime)
            revert EarlyUnstakingNotAllowed();

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
            ) revert StakingAmountTooLow();

            if (
                userStake.durationIndex == 4 &&
                userStake.amountWithPrecision < 5000e8 * 10 ** PRECISION_FACTOR
            ) revert Minimum5000MELStakeRequired();
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
     * @dev Internal function to get the staking program name from duration index
     * @param durationIndex Index representing the staking duration
     * @return Program name as string
     */
    function getStakingProgramName(
        uint8 durationIndex
    ) internal pure returns (string memory) {
        if (durationIndex == 0) return "NO_LOCK";
        if (durationIndex == 1) return "LUNAR"; // 3 months / 90 days
        if (durationIndex == 2) return "SOLAR"; // 6 months / 180 days
        if (durationIndex == 3) return "PULSAR"; // 12 months / 365 days
        if (durationIndex == 4) return "GENESIS"; // 12 months / 365 days
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

        // LUNAR (3 months lock-up) - index 1
        if (durationIndex == 1) {
            if (monthsElapsed == 0) return 9000; // 90%
            if (monthsElapsed == 1) return 6000; // 60%
            if (monthsElapsed == 2) return 3000; // 30%
            return 0; // After 3 months, no burn
        }

        // SOLAR (6 months lock-up) - index 2
        if (durationIndex == 2) {
            if (monthsElapsed == 0) return 9000; // 90%
            if (monthsElapsed == 1) return 7500; // 75%
            if (monthsElapsed == 2) return 6000; // 60%
            if (monthsElapsed == 3) return 4500; // 45%
            if (monthsElapsed == 4) return 3000; // 30%
            if (monthsElapsed == 5) return 1500; // 15%
            return 0; // After 6 months, no burn
        }

        // PULSAR & GENESIS (12 months lock-up) - index 3 & 4
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
    function claimRewards(uint256 stakeIndex) external nonReentrant {
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
     * @dev Updates accumulated rewards for all stakers
     * Can only be called by admin and once per day
     */
    function updateAccumulatedRewards() external onlyRole(ADMIN_ROLE) {
        // Allow 1 minute of leeway to avoid issues with block timestamp
        if (block.timestamp < lastUpdateTime + 1 days - 1 minutes)
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
            lastUpdateTime = uint32(block.timestamp);

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
     * @dev Toggles compound rewards for a specific stake
     * @param stakeIndex Index of the stake to toggle compound rewards
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
     * @dev Returns the total amount of staked tokens
     * @return Total staked amount
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStakedWithPrecision / 10 ** PRECISION_FACTOR;
    }

    /**
     * @dev Returns the total ponderated amount of staked tokens
     * @return Total ponderated staked amount
     */
    function getTotalPonderatedStaked() external view returns (uint256) {
        return totalPonderatedStakedWithPrecision / 10 ** PRECISION_FACTOR;
    }

    /**
     * @dev Returns all stakes for a specific user
     * @param user Address of the user
     * @return Array of StakingInfo structs
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

    // View functions for early unstaking information

    /**
     * @dev Returns the staking program name for a given duration index
     * @param durationIndex Index representing the staking duration
     * @return programName Name of the staking program
     */
    function getStakingProgramNameView(
        uint8 durationIndex
    ) external pure returns (string memory programName) {
        return getStakingProgramName(durationIndex);
    }

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
     * @return programName Name of the staking program
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
            uint256 monthsElapsed,
            string memory programName
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
        programName = getStakingProgramName(userStake.durationIndex);

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

    /**
     * @dev Checks if early unstaking is allowed for a specific stake
     * @param user Address of the user
     * @param stakeIndex Index of the stake
     * @return isAllowed Whether early unstaking is allowed
     * @return reason Reason if not allowed (empty string if allowed)
     */
    function canEarlyUnstake(
        address user,
        uint256 stakeIndex
    ) external view returns (bool isAllowed, string memory reason) {
        if (stakeIndex >= userStakes[user].length) {
            return (false, "Invalid stake index");
        }

        StakingInfo storage userStake = userStakes[user][stakeIndex];

        if (userStake.durationIndex == 0) {
            return (false, "Cannot early unstake no-lock staking");
        }

        if (block.timestamp >= userStake.endTime) {
            return (false, "Lock period has ended, use regular unstake");
        }

        if (isRewardUpdating) {
            return (false, "Rewards are being updated");
        }

        return (true, "");
    }
}
