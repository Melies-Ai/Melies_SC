// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMeliesStaking
 * @dev Interface for the Melies staking contract.
 * This interface defines the external functions, events, and structs
 * for managing token staking with different lock periods and reward calculations.
 *
 * @author Melies Team
 */
interface IMeliesStaking {
    // ============ STRUCTS ============

    /**
     * @dev Struct to store staking information for each user's stake
     * @param amountWithPrecision Staked amount with precision factor
     * @param ponderatedAmountWithPrecision Ponderated staked amount with precision factor
     * @param accumulatedRewardsWithPrecision Accumulated rewards with precision factor
     * @param startTime Timestamp when staking started
     * @param endTime Timestamp when staking period ends (0 for no lock)
     * @param lastClaimTime Timestamp of last reward claim
     * @param durationIndex Index representing the staking duration (0-4)
     * @param compoundRewards Whether rewards are compounded
     */
    struct StakingInfo {
        uint256 amountWithPrecision;
        uint256 ponderatedAmountWithPrecision;
        uint256 accumulatedRewardsWithPrecision;
        uint32 startTime;
        uint32 endTime;
        uint32 lastClaimTime;
        uint8 durationIndex;
        bool compoundRewards;
    }

    // ============ EVENTS ============

    /**
     * @dev Emitted when tokens are staked
     * @param user Address of the user who staked
     * @param amount Amount of tokens staked
     * @param durationIndex Index representing the staking duration
     */
    event Staked(address indexed user, uint256 amount, uint8 durationIndex);

    /**
     * @dev Emitted when tokens are unstaked
     * @param user Address of the user who unstaked
     * @param amount Amount of tokens unstaked
     * @param rewards Amount of rewards claimed
     */
    event Unstaked(address indexed user, uint256 amount, uint256 rewards);

    /**
     * @dev Emitted when rewards are claimed
     * @param user Address of the user who claimed rewards
     * @param amount Amount of rewards claimed
     */
    event RewardsClaimed(address indexed user, uint256 amount);

    /**
     * @dev Emitted when tokens are unstaked early with burn penalty
     * @param user Address of the user who unstaked early
     * @param amount Amount of tokens unstaked
     * @param rewards Amount of rewards claimed
     * @param burnAmount Amount of tokens burned as penalty
     * @param durationIndex Index representing the staking duration
     * @param monthsElapsed Number of months elapsed since staking
     */
    event EarlyUnstaked(
        address indexed user,
        uint256 amount,
        uint256 rewards,
        uint256 burnAmount,
        uint8 durationIndex,
        uint256 monthsElapsed
    );

    /**
     * @dev Emitted when TGE timestamp is set
     * @param tgeTimestamp The TGE timestamp
     */
    event TgeTimestampSet(uint256 tgeTimestamp);

    // ============ ERRORS ============

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

    // ============ FUNCTIONS ============

    /**
     * @dev Sets the TGE timestamp (one-time only, admin only)
     * @param _tgeTimestamp The TGE timestamp to set
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - TGE timestamp must not already be set
     * - TGE timestamp must be valid
     *
     * Emits a {TgeTimestampSet} event.
     */
    function setTgeTimestamp(uint32 _tgeTimestamp) external;

    /**
     * @dev Allows users to stake their tokens
     * @param _amount Amount of tokens to stake
     * @param _durationIndex Index representing the staking duration
     * @param _compoundRewards Whether to compound rewards or not
     *
     * Requirements:
     * - Amount must be at least minimum stake amount
     * - Duration index must be valid
     * - TGE timestamp must be set
     * - Cannot stake with index 4 after 90 days from TGE
     *
     * Emits a {Staked} event.
     */
    function stake(
        uint256 _amount,
        uint8 _durationIndex,
        bool _compoundRewards
    ) external;

    /**
     * @dev Allows users to unstake their tokens and claim rewards
     * @param _stakeIndex Index of the stake to unstake
     * @param _ponderatedAmountWithPrecision Amount to unstake with precision
     *
     * Requirements:
     * - Staking period must have ended
     * - Amount must not exceed staked amount
     * - Remaining amount must meet minimum requirements
     *
     * Emits an {Unstaked} event.
     */
    function unstake(
        uint256 _stakeIndex,
        uint256 _ponderatedAmountWithPrecision
    ) external;

    /**
     * @dev Allows users to unstake their tokens early with burn penalty
     * @param _stakeIndex Index of the stake to unstake
     * @param _ponderatedAmountWithPrecision Amount to unstake with precision
     *
     * Requirements:
     * - Cannot be used for no-lock staking (index 0)
     * - Must be before the lock period ends
     * - Burn percentage is applied based on staking program and elapsed time
     *
     * Emits an {EarlyUnstaked} event.
     */
    function earlyUnstake(
        uint256 _stakeIndex,
        uint256 _ponderatedAmountWithPrecision
    ) external;

    /**
     * @dev Allows users to claim their accumulated rewards
     * @param stakeIndex Index of the stake to claim rewards from
     *
     * Requirements:
     * - Stake index must be valid
     * - There must be rewards to claim
     *
     * Emits a {RewardsClaimed} event.
     */
    function claimRewards(uint256 stakeIndex) external;

    /**
     * @dev Updates accumulated rewards for all stakers
     * Can only be called by admin and once per day
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Can only be called once per day
     */
    function updateAccumulatedRewards() external;

    /**
     * @dev Toggles compound rewards for a specific stake
     * @param stakeIndex Index of the stake to toggle compound rewards
     *
     * Requirements:
     * - Can only be used for no-lock staking (index 0)
     */
    function toggleCompoundRewards(uint256 stakeIndex) external;

    /**
     * @dev Pauses the contract
     * Can only be called by admin
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function pause() external;

    /**
     * @dev Unpauses the contract
     * Can only be called by admin
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function unpause() external;

    /**
     * @dev Allows admin to withdraw tokens in case of emergency
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function emergencyWithdraw(address token, uint256 amount) external;

    /**
     * @dev Allows admin to change the DURATION_MULTIPLIERS
     * @param newMultipliers New array of duration multipliers
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Multipliers must be valid (increasing order)
     */
    function setDurationMultipliers(uint16[5] memory newMultipliers) external;

    /**
     * @dev Allows admin to change the DAILY_BUDGET_TARGET
     * @param newDailyBudget New daily budget target
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - New daily budget must be greater than 0
     */
    function setDailyBudgetTarget(uint256 newDailyBudget) external;

    /**
     * @dev Allows admin to change the MIN_STAKE_AMOUNT
     * @param newMinStakeAmount New minimum stake amount
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function setMinStakeAmount(uint256 newMinStakeAmount) external;

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Returns the total amount of staked tokens
     * @return Total staked amount
     */
    function getTotalStaked() external view returns (uint256);

    /**
     * @dev Returns the total ponderated amount of staked tokens
     * @return Total ponderated staked amount
     */
    function getTotalPonderatedStaked() external view returns (uint256);

    /**
     * @dev Returns all stakes for a specific user
     * @param user Address of the user
     * @return Array of StakingInfo structs
     */
    function getUserStakes(
        address user
    ) external view returns (StakingInfo[] memory);

    /**
     * @dev Returns the total amount of stakes for a specific user
     * @param user Address of the user
     * @return totalStakes Total amount of stakes for the user
     */
    function getTotalUserStakes(
        address user
    ) external view returns (uint256 totalStakes);

    /**
     * @dev Checks if TGE timestamp has been set
     * @return True if TGE timestamp has been set
     */
    function isTgeTimestampSet() external view returns (bool);

    /**
     * @dev Calculates the burn percentage for early unstaking preview
     * @param durationIndex Index representing the staking duration
     * @param monthsElapsed Number of full months elapsed since staking
     * @return burnPercentage Percentage to burn (0-9000 representing 0-90%)
     */
    function getEarlyUnstakingBurnPercentage(
        uint8 durationIndex,
        uint256 monthsElapsed
    ) external pure returns (uint256 burnPercentage);

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
        );

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
    ) external view returns (uint256, uint256);

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
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);
}
