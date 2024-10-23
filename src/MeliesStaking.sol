// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MeliesStaking
 * @dev Manages the staking mechanism for Melies tokens.
 * Implements flexible staking options with different lock periods,
 * reward calculations based on staking duration, compound rewards,
 * and admin functions for staking management.
 */
contract MeliesStaking is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    error AmountMustBeGreaterThanZero();
    error InvalidDurationIndex();
    error CannotStakeAfter90DaysFromTGE();
    error InvalidStakeIndex();
    error StakingPeriodNotEnded();
    error AmountGreaterThanStakeAmount();
    error AmountGreaterThanPonderatedStakeAmount();
    error NoRewardsToClaim();
    error CanOnlyUpdateOncePerDay();
    error CanOnlyToggleForNoLockStaking();
    error StakingAmountTooLow();
    error InvalidMultiplier();
    error DailyBudgetMustBeGreaterThanZero();

    IERC20 public meliesToken;

    uint256 private constant ANNUAL_BUDGET = 2_280_000e8; // 2.28M tokens
    uint256 public DAILY_BUDGET_TARGET =
        (ANNUAL_BUDGET / 365) * 10 ** PRECISION_FACTOR;
    uint256 private constant DURATION_MULTIPLIER_PRECISION = 2;
    uint256 private constant PRECISION_FACTOR = 12;
    uint256 private constant GAS_LIMIT_EXECUTION = 100_000;
    uint256 public MIN_STAKE_AMOUNT = 100e8;
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

    /**
     * @dev Constructor to initialize the MeliesStaking contract
     * @param _meliesToken Address of the Melies token contract
     * @param _tgeTimestamp Timestamp for the Token Generation Event (TGE)
     */
    constructor(address _meliesToken, uint32 _tgeTimestamp) {
        meliesToken = IERC20(_meliesToken);
        tgeTimestamp = _tgeTimestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Allows users to stake their tokens
     * @param _amount Amount of tokens to stake
     * @param _durationIndex Index representing the staking duration
     * @param _compoundRewards Whether to compound rewards or not
     */
    function stake(
        uint256 _amount,
        uint8 _durationIndex,
        bool _compoundRewards
    ) external whenNotPaused nonReentrant {
        if (isRewardUpdating) revert RewardsBeingUpdated();
        if (_amount == 0) revert AmountMustBeGreaterThanZero();
        if (_amount < MIN_STAKE_AMOUNT) revert StakingAmountTooLow();
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
            totalStakedWithPrecision -= amountWithPrecision;
            totalPonderatedStakedWithPrecision -= _ponderatedAmountWithPrecision;
            userStake.amountWithPrecision -= amountWithPrecision;
            userStake
                .ponderatedAmountWithPrecision -= _ponderatedAmountWithPrecision;
        }
        userStake.accumulatedRewardsWithPrecision = 0;

        meliesToken.safeTransfer(msg.sender, unstakeAmount);

        if (userStake.amountWithPrecision == 0) {
            // Remove the stake by swapping with the last element and popping
            userStakes[msg.sender][_stakeIndex] = userStakes[msg.sender][
                userStakes[msg.sender].length - 1
            ];
            userStakes[msg.sender].pop();
        }

        emit Unstaked(
            msg.sender,
            amountWithPrecision / 10 ** PRECISION_FACTOR,
            rewardsWithPrecision / 10 ** PRECISION_FACTOR
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

        // Update rewards for stakers until we run out of gas or process all stakers
        while (i < stakers.length && gasleft() > GAS_LIMIT_EXECUTION) {
            address user = stakers[i];
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
}
