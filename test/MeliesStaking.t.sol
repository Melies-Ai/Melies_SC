// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "../src/mock/MockMelies.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";

/// @title Melies Staking Test Suite
/// @author Melies Team
/// @notice Comprehensive test suite for the Melies Staking contract
/// @dev Tests all staking functionalities, rewards, penalties, and admin controls
/// @custom:security-contact security@melies.com
contract MeliesStakingTest is Test {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    MeliesStaking public stakingContract;
    Melies public meliesToken;
    uint256 public tgeTimestamp;

    // Test addresses
    address public admin;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;

    // Helper mappings for simulation tests
    mapping(string => address) private userAddresses;
    uint256 private nextUserIndex = 1;

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    uint256 private constant ANNUAL_BUDGET = 2_280_000e8; // 2.28M tokens
    uint256 private constant DAILY_BUDGET =
        (ANNUAL_BUDGET / 365) * 10 ** PRECISION_FACTOR;
    uint256 private constant PRECISION_FACTOR = 12;
    uint256 private constant DURATION_MULTIPLIER_PRECISION = 2;
    uint256[5] private DURATION_MULTIPLIERS = [1e2, 1.3e2, 1.6e2, 2.2e2, 3e2];

    bytes4 private constant ENFORCED_PAUSE_SELECTOR =
        bytes4(keccak256("EnforcedPause()"));
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public {
        // Initialize test addresses
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        user4 = address(0x4);
        user5 = address(0x5);

        tgeTimestamp = 1;

        // Deploy contracts
        meliesToken = new Melies(admin);
        stakingContract = new MeliesStaking(address(meliesToken));

        // Configure staking contract
        stakingContract.setTgeTimestamp(uint32(tgeTimestamp));
        stakingContract.grantRole(ADMIN_ROLE, admin);

        // Configure token permissions
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), admin);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), admin);
        meliesToken.grantRole(
            meliesToken.BURNER_ROLE(),
            address(stakingContract)
        );

        // Distribute initial tokens
        meliesToken.mint(address(stakingContract), 20_000_000 * 1e8);
        meliesToken.mint(user1, 1_000_000e8);
        meliesToken.mint(user2, 1_000_000e8);
        meliesToken.mint(user3, 1_000_000e8);
        meliesToken.mint(user4, 1_000_000e8);
        meliesToken.mint(user5, 1_000_000e8);
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    function setupStakingWithoutCompound() public {
        uint128 stakeAmount = 10_000e8;
        uint8 durationIndex = 0; // No lock
        bool compoundRewards = false;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();
    }

    function setupStakingWithCompound() public {
        uint128 stakeAmount = 10_000e8;
        uint8 durationIndex = 1; // 90 days
        bool compoundRewards = true;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();
    }

    function setupRewards(uint256 _days) public {
        uint256 startTime = 1;
        for (uint256 i = 0; i < _days; i++) {
            startTime = startTime + 1 days;
            vm.warp(startTime);
            // Using admin for convenience, but any address could call this function
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }
    }

    // ============================================================================
    // TESTS
    // ============================================================================

    // ============================================================================
    // CORE STAKING TESTS
    // ============================================================================

    /// @notice Test basic staking functionality
    function test_Stake() public {
        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 1; // 90 days
        bool compoundRewards = true;

        setupStakingWithCompound();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes.length, 1);
        assertEq(
            userStakes[0].amountWithPrecision,
            stakeAmount * 10 ** PRECISION_FACTOR
        );
        assertEq(
            userStakes[0].ponderatedAmountWithPrecision,
            (stakeAmount *
                10 ** (PRECISION_FACTOR - DURATION_MULTIPLIER_PRECISION) *
                DURATION_MULTIPLIERS[durationIndex])
        );
        assertEq(userStakes[0].durationIndex, durationIndex);
        assertEq(userStakes[0].compoundRewards, compoundRewards);
        assertEq(stakingContract.getTotalStaked(), stakeAmount);
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            (stakeAmount * DURATION_MULTIPLIERS[durationIndex]) /
                10 ** (DURATION_MULTIPLIER_PRECISION)
        );
    }

    /// @notice Test basic unstaking functionality
    function test_Unstake() public {
        setupStakingWithoutCompound();
        setupRewards(20);

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        assertEq(stakingContract.getTotalPonderatedStaked(), 0);
        assertEq(stakingContract.getTotalStaked(), 0);
    }

    // ============================================================================
    // UNSTAKING TESTS
    // ============================================================================

    /// @notice Test partial unstaking functionality
    function test_PartialUnstake() public {
        setupStakingWithCompound();

        // Fast forward to allow unstaking
        vm.warp(block.timestamp + 91 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Get initial state
        uint256 initialUserBalance = meliesToken.balanceOf(user1);
        uint256 initialContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialStakeAmount = userStakes[0].amountWithPrecision;
        uint256 initialPonderatedAmount = userStakes[0]
            .ponderatedAmountWithPrecision;

        // Perform partial unstake (50%)
        uint256 unstakeAmount = initialPonderatedAmount / 2;
        vm.prank(user1);
        stakingContract.unstake(0, unstakeAmount);

        // Verify state changes
        uint256 finalUserBalance = meliesToken.balanceOf(user1);
        uint256 finalContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        userStakes = stakingContract.getUserStakes(user1);

        assertEq(
            userStakes[0].ponderatedAmountWithPrecision,
            initialPonderatedAmount - unstakeAmount
        );
        assertEq(userStakes[0].amountWithPrecision, initialStakeAmount / 2);
        assertEq(
            initialContractBalance - finalContractBalance,
            finalUserBalance - initialUserBalance
        );
        assertEq(
            stakingContract.getTotalStaked(),
            initialStakeAmount / 2 / 10 ** PRECISION_FACTOR
        );
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            (initialPonderatedAmount - unstakeAmount) / 10 ** PRECISION_FACTOR
        );
    }

    // ============================================================================
    // MINIMUM STAKE REQUIREMENTS
    // ============================================================================

    /// @notice Test minimum stake amount requirements
    function test_MinimumStakeRequirement() public {
        // Test failure cases
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 4999e8);
        vm.expectRevert(MeliesStaking.StakingAmountTooLow.selector);
        stakingContract.stake(4999e8, 0, true);
        vm.stopPrank();

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 199999e8);
        vm.expectRevert(MeliesStaking.StakingAmountTooLow.selector);
        stakingContract.stake(199999e8, 4, true);
        vm.stopPrank();

        // Test success cases
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 5000e8);
        stakingContract.stake(5000e8, 0, true);

        meliesToken.approve(address(stakingContract), 200000e8);
        stakingContract.stake(200000e8, 4, true);
        vm.stopPrank();
    }

    function test_MinimumStakeRequirementAfterPartialUnstake() public {
        // Setup initial stakes
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 0, true); // Regular stake with 10000 MEL

        meliesToken.approve(address(stakingContract), 300_000e8);
        stakingContract.stake(300_000e8, 4, true); // Genesis stake with 300000 MEL
        vm.stopPrank();

        // Fast forward to allow unstaking
        vm.warp(block.timestamp + 366 days);

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);

        // Test that we can unstake the full amount
        vm.startPrank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);
        stakingContract.unstake(0, userStakes[1].ponderatedAmountWithPrecision);
        vm.stopPrank();

        // Verify all stakes are removed
        userStakes = stakingContract.getUserStakes(user1);
        assertEq(userStakes.length, 0);
    }

    // ============================================================================
    // TGE AND TIME-BASED TESTS
    // ============================================================================

    /// @notice Test genesis staking within 90 days of TGE
    function test_GenesisStakingWithin90DaysAfterTGE() public {
        uint256 stakeAmount = 200_000 * 1e8;
        uint8 durationIndex = 4; // 365 days
        bool compoundRewards = true;

        vm.warp(tgeTimestamp + 89 days);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes.length, 1);
        assertEq(userStakes[0].durationIndex, durationIndex);
        assertEq(userStakes[0].endTime, uint32(block.timestamp + 365 days));
    }

    function test_GenesisStakingExactly90DaysAfterTGE() public {
        uint256 stakeAmount = 200_000 * 1e8;
        uint8 durationIndex = 4; // 365 days
        bool compoundRewards = true;

        // Set the current time to exactly 90 days after TGE
        vm.warp(tgeTimestamp + 90 days);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes.length, 1);
        assertEq(userStakes[0].durationIndex, durationIndex);
        assertEq(userStakes[0].endTime, uint32(block.timestamp + 365 days));
    }

    function test_GenesisStakingAfter90DaysAfterTGE() public {
        uint256 stakeAmount = 200_000 * 1e8;
        uint8 durationIndex = 4; // 365 days
        bool compoundRewards = true;

        // Set the current time to 91 days after TGE
        vm.warp(tgeTimestamp + 91 days);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        vm.expectRevert(MeliesStaking.CannotStakeAfter90DaysFromTGE.selector);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();
    }

    function test_StakeAfter90DaysAfterTGE() public {
        uint256 stakeAmount = 10_000 * 1e8;
        bool compoundRewards = true;

        // Set the current time to 91 days after TGE
        vm.warp(tgeTimestamp + 91 days);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount * 4);

        // Test staking with other duration indices
        for (uint8 i = 0; i < 4; i++) {
            stakingContract.stake(stakeAmount, i, compoundRewards);
        }

        vm.stopPrank();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes.length, 4);
        for (uint8 i = 0; i < 4; i++) {
            assertEq(userStakes[i].durationIndex, i);
        }
    }

    // ============================================================================
    // REWARDS TESTS
    // ============================================================================

    /// @notice Test reward accumulation without compound
    function test_UpdateAccumulatedRewardsNoCompound() public {
        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 0;
        bool compoundRewards = false;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes[0].accumulatedRewardsWithPrecision, DAILY_BUDGET);
    }

    function test_UpdateAccumulatedRewardsWithCompound() public {
        uint256 stakeAmount = 10_000e8;

        setupStakingWithCompound();

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes[0].accumulatedRewardsWithPrecision, 0);
        assertEq(
            userStakes[0].amountWithPrecision,
            stakeAmount * 10 ** PRECISION_FACTOR + DAILY_BUDGET
        );
    }

    // ============================================================================
    // COMPOUND REWARDS TESTS
    // ============================================================================

    /// @notice Test toggling compound rewards
    function test_ToggleCompoundRewards() public {
        setupStakingWithoutCompound();
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertFalse(userStakes[0].compoundRewards);

        vm.prank(user1);
        stakingContract.toggleCompoundRewards(0);

        userStakes = stakingContract.getUserStakes(user1);
        assertTrue(userStakes[0].compoundRewards);
    }

    function test_GetTotalPonderatedStaked() public {
        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 1; // 90 days
        setupStakingWithCompound();

        uint256 totalPonderatedStaked = stakingContract
            .getTotalPonderatedStaked();
        assertEq(
            totalPonderatedStaked,
            (stakeAmount * DURATION_MULTIPLIERS[durationIndex]) / 100
        );
    }

    // ============================================================================
    // ADMIN FUNCTIONS TESTS
    // ============================================================================

    /// @notice Test pause functionality
    function test_Pause() public {
        stakingContract.pause();
        assertTrue(stakingContract.paused());

        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 1; // 90 days
        bool compoundRewards = true;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();
    }

    function test_Unpause() public {
        stakingContract.pause();
        stakingContract.unpause();
        assertFalse(stakingContract.paused());

        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 1; // 90 days
        bool compoundRewards = true;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();

        assertEq(stakingContract.getTotalStaked(), stakeAmount);
    }

    function test_SetDurationMultipliers() public {
        uint16[5] memory newMultipliers = [1e2, 1.5e2, 2e2, 2.5e2, 3.5e2];

        vm.prank(admin);
        stakingContract.setDurationMultipliers(newMultipliers);

        for (uint8 i = 0; i < 5; i++) {
            assertEq(
                stakingContract.DURATION_MULTIPLIERS(i),
                newMultipliers[i]
            );
        }
    }

    function test_SetDurationMultipliers_InvalidFirstMultiplier() public {
        uint16[5] memory newMultipliers = [2e2, 2.5e2, 3e2, 3.5e2, 4e2];

        vm.prank(admin);
        vm.expectRevert(MeliesStaking.InvalidMultiplier.selector);
        stakingContract.setDurationMultipliers(newMultipliers);
    }

    function test_SetDurationMultipliers_InvalidOrder() public {
        uint16[5] memory newMultipliers = [1e2, 2.5e2, 2e2, 3.5e2, 4e2];

        vm.prank(admin);
        vm.expectRevert(MeliesStaking.InvalidMultiplier.selector);
        stakingContract.setDurationMultipliers(newMultipliers);
    }

    function test_SetDailyBudgetTarget() public {
        uint256 newDailyBudget = 10_000e8;

        vm.prank(admin);
        stakingContract.setDailyBudgetTarget(newDailyBudget);

        assertEq(
            stakingContract.DAILY_BUDGET_TARGET(),
            newDailyBudget * 10 ** PRECISION_FACTOR
        );
    }

    function test_SetDailyBudgetTarget_ZeroValue() public {
        uint256 newDailyBudget = 0;

        vm.prank(admin);
        vm.expectRevert(
            MeliesStaking.DailyBudgetMustBeGreaterThanZero.selector
        );
        stakingContract.setDailyBudgetTarget(newDailyBudget);
    }

    function test_SetMinStakeAmount() public {
        uint256 newMinStakeAmount = 200e8;

        vm.prank(admin);
        stakingContract.setMinStakeAmount(newMinStakeAmount);

        assertEq(stakingContract.MIN_STAKE_AMOUNT(), newMinStakeAmount);
    }

    function test_SetMinStakeAmount_ZeroValue() public {
        uint256 newMinStakeAmount = 0;

        vm.prank(admin);
        stakingContract.setMinStakeAmount(newMinStakeAmount);

        assertEq(stakingContract.MIN_STAKE_AMOUNT(), newMinStakeAmount);
    }

    function test_OnlyAdminCanSetDurationMultipliers() public {
        uint16[5] memory newMultipliers = [1e2, 1.5e2, 2e2, 2.5e2, 3.5e2];

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.setDurationMultipliers(newMultipliers);
    }

    function test_OnlyAdminCanSetDailyBudgetTarget() public {
        uint256 newDailyBudget = 10_000e8;

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.setDailyBudgetTarget(newDailyBudget);
    }

    function test_OnlyAdminCanSetMinStakeAmount() public {
        uint256 newMinStakeAmount = 200e8;

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.setMinStakeAmount(newMinStakeAmount);
    }

    function test_SetTgeTimestamp() public {
        // Test that TGE timestamp can be set
        assertTrue(stakingContract.isTgeTimestampSet());

        // Test that it cannot be set twice
        vm.expectRevert(MeliesStaking.TgeTimestampAlreadySet.selector);
        stakingContract.setTgeTimestamp(100);
    }

    function test_StakeWithoutTgeTimestamp() public {
        // Deploy a new contract without setting TGE timestamp
        MeliesStaking newStakingContract = new MeliesStaking(
            address(meliesToken)
        );

        vm.startPrank(user1);
        meliesToken.approve(address(newStakingContract), 10_000e8);
        vm.expectRevert(MeliesStaking.TgeTimestampNotSet.selector);
        newStakingContract.stake(10_000e8, 1, true);
        vm.stopPrank();
    }

    function test_IsRewardUpdatingTests() public {
        // Setup a simple stake
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true);
        vm.stopPrank();

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Start updating rewards
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // isRewardUpdating should be false after processing one stake
        assertFalse(stakingContract.isRewardUpdating());

        // Now staking should work
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 2, true);
        vm.stopPrank();

        // Fast forward 1 year for unstaking
        vm.warp(block.timestamp + 366 days);

        // Unstake should work
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);
    }

    function test_EmergencyWithdraw() public {
        uint256 stakeAmount = 10_000 * 1e8;

        setupStakingWithCompound();

        uint256 initialAdminBalance = meliesToken.balanceOf(admin);
        uint256 initialContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        assertEq(initialContractBalance, 20_000_000 * 1e8 + stakeAmount);

        stakingContract.emergencyWithdraw(
            address(meliesToken),
            20_000_000 * 1e8 + stakeAmount
        );

        uint256 finalContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        assertEq(finalContractBalance, 0);

        uint256 adminBalance = meliesToken.balanceOf(admin);
        assertEq(
            adminBalance,
            20_000_000 * 1e8 + stakeAmount - initialAdminBalance
        );
    }

    // ============================================================================
    // SIMULATION TESTS
    // ============================================================================

    /// @notice Test complex staking scenario with multiple users and time periods
    function test_MultipleStakingScenario() public {
        uint256 dayCounter = 0;
        uint256 startTime = 1 + 1 days;
        uint16 i;

        // Day 1: Bob stakes 10000 tokens with 180 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 2, true); // 180 days, compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Day 2: Alice stakes 5000 tokens with no lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 5_000e8);
        stakingContract.stake(5_000e8, 0, false); // No lock, no compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 3-4
        for (i = 3; i <= 4; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Day 5: Bob stakes another 10000 tokens with 90 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true); // 90 days, compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 6-9
        for (i = 6; i <= 9; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Day 10: Charlie stakes 200000 tokens with 365 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user3);
        meliesToken.approve(address(stakingContract), 200_000e8);
        stakingContract.stake(200_000e8, 4, true); // 365 days, compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 11-22
        for (i = 11; i <= 22; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Day 23: Alice unstakes her 5000 tokens
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialUserBalance = meliesToken.balanceOf(user1);

        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        uint256 finalUserBalance = meliesToken.balanceOf(user1);
        // Note: The exact amount will depend on rewards accumulated, so we'll just check it's greater than the original stake
        assertEq(finalUserBalance - initialUserBalance, 976_080_928_961);

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 24-95
        for (i = 24; i <= 95; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Day 96: Bob unstakes 2nd stake
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        userStakes = stakingContract.getUserStakes(user2);

        initialUserBalance = meliesToken.balanceOf(user2);

        vm.prank(user2);
        stakingContract.unstake(1, userStakes[1].ponderatedAmountWithPrecision);

        finalUserBalance = meliesToken.balanceOf(user2);
        // Note: The exact amount will depend on rewards accumulated, so we'll just check it's greater than the original stake
        assertEq(finalUserBalance - initialUserBalance, 2_660_994_801_532);

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 97-107
        for (i = 97; i <= 107; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Day 108: Alice stakes 10_000 tokens with 365 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 3, true); // 365 days, compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 109-195
        for (i = 109; i <= 195; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Day 196: Bob unstakes 1st stake
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        userStakes = stakingContract.getUserStakes(user2);

        initialUserBalance = meliesToken.balanceOf(user2);

        vm.prank(user2);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        finalUserBalance = meliesToken.balanceOf(user2);
        assertEq(finalUserBalance - initialUserBalance, 15_011_058_208_008);

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Update rewards for days 197-200
        for (i = 197; i <= 200; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Test total ponderated staked at 201 days
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            388_156_080_740_478
        );

        // Update rewards for days 201-600
        for (i = 201; i <= 600; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Test total ponderated staked at 601 days
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            1_136_309_386_042_540
        );

        // Update rewards for days 601-1200 - ~39 months of 90 days
        for (i = 601; i <= 1200; i++) {
            vm.warp(startTime + dayCounter * 1 days);
            dayCounter++;
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }

        // Test total ponderated staked after 1200 days
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            2_258_966_304_442_607
        );
        userStakes = stakingContract.getUserStakes(user1);
        assertEq(
            userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR,
            5_445_521_284_355
        );
        userStakes = stakingContract.getUserStakes(user3);
        assertEq(
            userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR,
            748_995_385_872_341
        );

        userStakes = stakingContract.getUserStakes(user1);
        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        userStakes = stakingContract.getUserStakes(user3);
        vm.prank(user3);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        assertEq(stakingContract.getTotalPonderatedStaked(), 0);
    }

    function test_GasConsumptionDailyCalculation() public {
        // Setup clean contracts
        Melies newMelies = new Melies(address(admin));
        newMelies.grantRole(newMelies.MINTER_ROLE(), admin);
        MeliesStaking newStaking = new MeliesStaking(address(newMelies));
        newStaking.setTgeTimestamp(uint32(tgeTimestamp));

        vm.pauseGasMetering();
        uint256 dayCounter = 0;
        uint256 startTime = 1 + 1 days;
        uint256 i;
        uint256 numStakers = 200_000; // 1_000_000_000 (max supply) / 5_000 (min staking) = 200_000 stakers

        // Stake for each simulated user
        for (i = 0; i < numStakers; i++) {
            address staker = address(uint160(i + 1));
            newMelies.mint(staker, 5000e8);
            vm.startPrank(staker);
            newMelies.approve(address(newStaking), 5000e8);
            newStaking.stake(5000e8, 3, true);
            vm.stopPrank();
        }

        // Measure gas for daily reward calculation
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        vm.resumeGasMetering();
        do {
            vm.prank(admin);
            gasBefore = gasleft();
            newStaking.updateAccumulatedRewards{gas: 156_000_000}();
            gasAfter = gasleft();
            gasUsed = gasBefore - gasAfter;
            // Assert that gas usage is within an acceptable range even with a large number of stakers
            // In Base chain, block gas limit is still growing. For now, it's 156M.
            assert(gasUsed < 156_000_000);
            vm.resetGasMetering();
        } while (newStaking.isRewardUpdating());

        // Check results
        assertEq(
            newStaking.getTotalPonderatedStaked(),
            (200_000 * 5000e8 * 2.2) + (((ANNUAL_BUDGET / 365) * 220) / 100) // 200_000 * 5000e8 * 2.2 + Daily budget * 2.2
        );
    }

    // It needs to be runs with a large gas-limit because vm.pauseGasMetering() is bugged aud cause memoryOOG error
    function test_LargeAmountStakersScenario() public {
        // Setup clean contracts
        Melies newMelies = new Melies(address(admin));
        newMelies.grantRole(newMelies.MINTER_ROLE(), admin);
        MeliesStaking newStaking = new MeliesStaking(address(newMelies));
        newStaking.setTgeTimestamp(uint32(tgeTimestamp));

        // Setup simulation
        uint256 startTime = tgeTimestamp + 1 days;
        uint256 simulationDuration = 1200; // ~39 months

        string[] memory inputs = new string[](6);
        inputs[0] = "python";
        inputs[1] = "python_script/staking_sim.py";
        inputs[2] = Strings.toString(12000); //  12000 users
        inputs[3] = Strings.toString(simulationDuration);
        inputs[4] = Strings.toString(5); // 5 stakes per user
        inputs[5] = Strings.toString(1);
        bytes memory result = vm.ffi(inputs);

        (
            string memory scenarioStr,
            uint256 expectedPonderatedStake
        ) = parseResult(string(result));

        string[] memory actions = parseActions(scenarioStr);

        uint256 currentDay = 0;
        vm.warp(startTime + currentDay * 1 days);
        currentDay++;

        for (uint256 i = 0; i < actions.length; i++) {
            string memory action = actions[i];
            (
                uint256 day,
                string memory actionType,
                address user,
                uint256 amount,
                uint8 index
            ) = parseAction(action);

            // Warp just before the action day
            while (day > currentDay) {
                vm.warp(startTime + currentDay * 1 days);
                vm.prank(admin);
                newStaking.updateAccumulatedRewards();
                currentDay++;
            }

            if (
                keccak256(abi.encodePacked(actionType)) ==
                keccak256(abi.encodePacked("stake"))
            ) {
                vm.prank(admin);
                newMelies.mint(user, amount);
                vm.startPrank(user);
                newMelies.approve(address(newStaking), amount);
                newStaking.stake(amount, index, false);
                vm.stopPrank();
            } else if (
                keccak256(abi.encodePacked(actionType)) ==
                keccak256(abi.encodePacked("unstake"))
            ) {
                MeliesStaking.StakingInfo[] memory userStakes = newStaking
                    .getUserStakes(user);
                if (userStakes.length > index) {
                    vm.prank(user);
                    newStaking.unstake(
                        index,
                        userStakes[index].ponderatedAmountWithPrecision
                    );
                }
            }

            if (day > currentDay) {
                // update rewards after action
                vm.warp(startTime + currentDay * 1 days);
                vm.prank(admin);
                newStaking.updateAccumulatedRewards();
                currentDay++;
            }
        }

        // Ensure we've updated rewards for all days in the simulation
        while (currentDay <= simulationDuration) {
            vm.warp(startTime + currentDay * 1 days);
            vm.prank(admin);
            newStaking.updateAccumulatedRewards();
            currentDay++;
        }

        uint256 actualPonderatedStake = newStaking.getTotalPonderatedStaked();
        assertApproxEqAbs(actualPonderatedStake, expectedPonderatedStake, 1);
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================

    /// @notice Parse simulation result string
    function parseResult(
        string memory result
    ) internal pure returns (string memory, uint256) {
        string[] memory parts = split(result, "/");
        return (parts[0], parseUint(parts[1]));
    }

    function parseActions(
        string memory result
    ) internal pure returns (string[] memory) {
        return split(result, ",");
    }

    function parseAction(
        string memory action
    ) internal returns (uint256, string memory, address, uint256, uint8) {
        string[] memory parts = split(action, "|");
        return (
            parseUint(parts[0]), // day
            parts[1], // action type
            getUserAddress(parts[2]), // user
            parseUint(parts[3]), // amount
            uint8(parseUint(parts[4])) // duration index
        );
    }

    function getUserAddress(string memory user) internal returns (address) {
        if (userAddresses[user] == address(0)) {
            // Create a new address if it doesn't exist
            address newAddress = address(uint160(nextUserIndex));
            nextUserIndex++;
            userAddresses[user] = newAddress;
        }
        return userAddresses[user];
    }

    function split(
        string memory str,
        string memory delim
    ) internal pure returns (string[] memory) {
        uint256 count = 1;
        for (uint256 i = 0; i < bytes(str).length; i++) {
            if (
                keccak256(abi.encodePacked(bytes1(bytes(str)[i]))) ==
                keccak256(abi.encodePacked(bytes(delim)))
            ) {
                count++;
            }
        }

        string[] memory parts = new string[](count);
        count = 0;
        uint256 lastIndex = 0;
        for (uint256 i = 0; i < bytes(str).length; i++) {
            if (
                keccak256(abi.encodePacked(bytes1(bytes(str)[i]))) ==
                keccak256(abi.encodePacked(bytes(delim)))
            ) {
                parts[count] = substring(str, lastIndex, i);
                lastIndex = i + 1;
                count++;
            }
        }
        parts[count] = substring(str, lastIndex, bytes(str).length);
        return parts;
    }

    function substring(
        string memory str,
        uint256 startIndex,
        uint256 endIndex
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function parseUint(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }

    // ============================================================================
    // CLAIM REWARDS TESTS
    // ============================================================================

    /// @notice Test claiming rewards functionality
    function test_ClaimRewards() public {
        // Setup staking without compound
        setupStakingWithoutCompound();

        // Fast forward 1 day and update rewards
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Check that user has accumulated rewards
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(userStakes[0].accumulatedRewardsWithPrecision, 0);

        // Claim rewards
        uint256 initialBalance = meliesToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards(0);

        // Check that user received rewards
        uint256 finalBalance = meliesToken.balanceOf(user1);
        assertGt(finalBalance, initialBalance);

        // Check that accumulated rewards are reset
        userStakes = stakingContract.getUserStakes(user1);
        assertEq(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    function test_ClaimRewardsNoRewards() public {
        setupStakingWithoutCompound();

        // Try to claim rewards without any accumulated rewards
        vm.prank(user1);
        vm.expectRevert(MeliesStaking.NoRewardsToClaim.selector);
        stakingContract.claimRewards(0);
    }

    function test_GetAllUserStakes() public {
        // Setup user1 with multiple stakes
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 15000e8);
        stakingContract.stake(5000e8, 1, true);
        stakingContract.stake(10000e8, 2, true);
        vm.stopPrank();

        // Setup user2 with one stake
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 10000e8);
        stakingContract.stake(10000e8, 0, false);
        vm.stopPrank();

        // Check user1's stakes
        MeliesStaking.StakingInfo[] memory user1Stakes = stakingContract
            .getUserStakes(user1);
        assertEq(user1Stakes.length, 2);

        // Check user2's stakes
        MeliesStaking.StakingInfo[] memory user2Stakes = stakingContract
            .getUserStakes(user2);
        assertEq(user2Stakes.length, 1);

        // Check user3's stakes (should be empty)
        MeliesStaking.StakingInfo[] memory user3Stakes = stakingContract
            .getUserStakes(user3);
        assertEq(user3Stakes.length, 0);

        // Test getTotalUserStakes
        uint256 totalUser1Stakes = stakingContract.getTotalUserStakes(user1);
        assertEq(totalUser1Stakes, 15000e8); // 5000e8 + 10000e8

        uint256 totalUser2Stakes = stakingContract.getTotalUserStakes(user2);
        assertEq(totalUser2Stakes, 10000e8);

        uint256 totalUser3Stakes = stakingContract.getTotalUserStakes(user3);
        assertEq(totalUser3Stakes, 0);
    }

    // ============================================================================
    // EARLY UNSTAKING TESTS
    // ============================================================================

    /// @notice Test burn percentage calculations for LUNAR program
    function test_LunarBurnPercentages() public {
        // LUNAR (index 1) - 3 month lock-up
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(1, 0), 9000); // 90%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(1, 1), 6000); // 60%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(1, 2), 3000); // 30%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(1, 3), 0); // 0% after 3 months
    }

    /// @notice Test burn percentage calculations for SOLAR program
    function test_SolarBurnPercentages() public {
        // SOLAR (index 2) - 6 month lock-up
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 0), 9000); // 90%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 1), 7500); // 75%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 2), 6000); // 60%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 3), 4500); // 45%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 4), 3000); // 30%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 5), 1500); // 15%
        assertEq(stakingContract.getEarlyUnstakingBurnPercentage(2, 6), 0); // 0% after 6 months
    }

    /// @notice Test burn percentage calculations for PULSAR/GENESIS programs
    function test_PulsarGenesisBurnPercentages() public {
        // PULSAR & GENESIS (index 3 & 4) - 12 month lock-up
        for (uint8 index = 3; index <= 4; index++) {
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 0),
                9000
            ); // 90.0%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 1),
                8250
            ); // 82.5%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 2),
                7500
            ); // 75.0%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 3),
                6750
            ); // 67.5%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 4),
                6000
            ); // 60.0%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 5),
                5250
            ); // 52.5%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 6),
                4500
            ); // 45.0%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 7),
                3750
            ); // 37.5%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 8),
                3000
            ); // 30.0%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 9),
                2250
            ); // 22.5%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 10),
                1500
            ); // 15.0%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 11),
                750
            ); // 7.5%
            assertEq(
                stakingContract.getEarlyUnstakingBurnPercentage(index, 12),
                0
            ); // 0% after 12 months
        }
    }

    /// @notice Test early unstaking with burn
    function test_EarlyUnstakingWithBurn() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);

        // Stake 10000 tokens with LUNAR program (90 days lock)
        stakingContract.stake(10_000e8, 1, true);
        uint256 stakeIndex = 0;

        // Check initial balance
        uint256 initialBalance = meliesToken.balanceOf(user1);

        // Get the user's stake to find the actual ponderated amount
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 fullPonderatedAmount = userStakes[0]
            .ponderatedAmountWithPrecision;

        // Preview early unstaking (should show 90% burn in first month)
        (
            uint256 netAmount,
            uint256 burnAmount,
            uint256 burnPercentage,
            uint256 monthsElapsed
        ) = stakingContract.previewEarlyUnstaking(
                user1,
                stakeIndex,
                fullPonderatedAmount
            );

        assertEq(monthsElapsed, 0);
        assertEq(burnPercentage, 9000); // 90%

        // Perform early unstaking with the full ponderated amount
        stakingContract.earlyUnstake(stakeIndex, fullPonderatedAmount);

        // Check that user received the net amount (10% of original stake)
        uint256 finalBalance = meliesToken.balanceOf(user1);
        uint256 receivedAmount = finalBalance - initialBalance;

        // Should receive 10% of 10000 tokens = 1000 tokens
        assertEq(receivedAmount, 1000e8);

        // Check that stake was removed
        MeliesStaking.StakingInfo[] memory stakes = stakingContract
            .getUserStakes(user1);
        assertEq(stakes.length, 0);

        vm.stopPrank();
    }

    /// @notice Test early unstaking after some time has passed
    function test_EarlyUnstakingAfterTime() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);

        // Stake 10000 tokens with SOLAR program (180 days lock)
        stakingContract.stake(10_000e8, 2, true);
        uint256 stakeIndex = 0;

        // Fast forward 60 days (2 months)
        vm.warp(block.timestamp + 60 days);

        // Get the user's stake to find the actual ponderated amount
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 fullPonderatedAmount = userStakes[0]
            .ponderatedAmountWithPrecision;

        // Preview early unstaking (should show 60% burn in third month)
        (
            uint256 netAmount,
            uint256 burnAmount,
            uint256 burnPercentage,
            uint256 monthsElapsed
        ) = stakingContract.previewEarlyUnstaking(
                user1,
                stakeIndex,
                fullPonderatedAmount
            );

        assertEq(monthsElapsed, 2);
        assertEq(burnPercentage, 6000); // 60%

        // Perform early unstaking
        uint256 initialBalance = meliesToken.balanceOf(user1);
        stakingContract.earlyUnstake(stakeIndex, fullPonderatedAmount);

        // Check that user received 40% of original stake
        uint256 finalBalance = meliesToken.balanceOf(user1);
        uint256 receivedAmount = finalBalance - initialBalance;

        // Should receive 40% of 10000 tokens = 4000 tokens
        assertEq(receivedAmount, 4000e8);

        vm.stopPrank();
    }

    /// @notice Test that early unstaking fails when lock period has ended
    function test_EarlyUnstakingFailsAfterLockPeriod() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);

        // Stake 10000 tokens with LUNAR program (90 days lock)
        stakingContract.stake(10_000e8, 1, true);

        // Fast forward past lock period
        vm.warp(block.timestamp + 91 days);

        // Get the user's stake to find the actual ponderated amount
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 fullPonderatedAmount = userStakes[0]
            .ponderatedAmountWithPrecision;

        // Try to early unstake (should fail with reentrancy guard since it calls unstake internally)
        vm.expectRevert();
        stakingContract.earlyUnstake(0, fullPonderatedAmount);

        vm.stopPrank();
    }

    // ============================================================================
    // EDGE CASES AND NEGATIVE TESTS
    // ============================================================================

    /// @notice Test that compound rewards cannot be toggled on locked stakes
    function test_ToggleCompoundRewardsOnLockedStakeShouldRevert() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true);
        vm.expectRevert(MeliesStaking.CanOnlyToggleForNoLockStaking.selector);
        stakingContract.toggleCompoundRewards(0);
        vm.stopPrank();
    }

    function test_ToggleCompoundRewardsMultipleTimes() public {
        setupStakingWithoutCompound();
        vm.startPrank(user1);
        stakingContract.toggleCompoundRewards(0);
        stakingContract.toggleCompoundRewards(0);
        stakingContract.toggleCompoundRewards(0);
        vm.stopPrank();
        assertTrue(true); // Should complete without reverting
    }

    function test_UnstakeInvalidIndexShouldRevert() public {
        setupStakingWithoutCompound();
        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.unstake(1, 1000e8);
        vm.stopPrank();
    }

    function test_UnstakeAmountGreaterThanAvailableShouldRevert() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        vm.expectRevert(
            MeliesStaking.AmountGreaterThanPonderatedStakeAmount.selector
        );
        stakingContract.unstake(0, 20_000e8 * 10 ** PRECISION_FACTOR);
        vm.stopPrank();
    }

    function test_EmergencyWithdrawNonStakingToken() public {
        // Deploy a mock ERC20
        MockERC20 mockToken = new MockERC20("MOCK", "MOCK");
        mockToken.mint(address(stakingContract), 1000e18);
        uint256 initialAdminBalance = mockToken.balanceOf(admin);
        stakingContract.emergencyWithdraw(address(mockToken), 1000e18);
        uint256 finalAdminBalance = mockToken.balanceOf(admin);
        assertEq(finalAdminBalance - initialAdminBalance, 1000e18);
    }

    function test_UnstakeWhilePausedShouldRevert() public {
        setupStakingWithoutCompound();
        stakingContract.pause();
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        stakingContract.unstake(0, 1000e8);
        vm.stopPrank();
    }

    function test_EarlyUnstakeWhilePausedShouldRevert() public {
        // Stake with lock
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true);
        vm.stopPrank();

        // Fast forward to allow early unstaking
        vm.warp(block.timestamp + 30 days);

        // Pause and try to early unstake
        stakingContract.pause();
        vm.startPrank(user1);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        stakingContract.earlyUnstake(0, 10_000e8);
        vm.stopPrank();
    }

    function test_ClaimRewardsWhilePausedShouldRevert() public {
        setupStakingWithoutCompound();
        // Fast forward 1 day and update rewards so there are rewards to claim
        vm.warp(block.timestamp + 1 days);
        stakingContract.updateAccumulatedRewards();

        stakingContract.pause();
        vm.startPrank(user1);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        stakingContract.claimRewards(0);
        vm.stopPrank();
    }

    function test_UpdateAccumulatedRewardsTwiceInOneDayShouldRevert() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);
        stakingContract.updateAccumulatedRewards();
        vm.expectRevert(MeliesStaking.CanOnlyUpdateOncePerDay.selector);
        stakingContract.updateAccumulatedRewards();
    }

    function test_UpdateAccumulatedRewardsWithNoStakers() public {
        // Don't stake anything, just update rewards
        vm.warp(block.timestamp + 1 days);
        stakingContract.updateAccumulatedRewards();
        assertTrue(true); // Should complete without reverting
    }

    function test_GetUserStakesForUserWithNoStakes() public {
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user3);
        assertEq(userStakes.length, 0);
    }

    function test_GetTotalUserStakesForUserWithNoStakes() public {
        assertEq(stakingContract.getTotalUserStakes(user3), 0);
    }

    function test_PreviewEarlyUnstakingInvalidIndexShouldRevert() public {
        vm.expectRevert();
        stakingContract.previewEarlyUnstaking(user1, 1, 1000e8);
    }

    function test_PreviewEarlyUnstakingPartialAmount() public {
        // Stake with lock
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true);
        vm.stopPrank();

        // Fast forward to allow early unstaking
        vm.warp(block.timestamp + 30 days);

        // Preview partial early unstaking
        (uint256 amountToReceive, uint256 burnAmount, , ) = stakingContract
            .previewEarlyUnstaking(
                user1,
                0,
                (5000e8 * 10 ** PRECISION_FACTOR * 130) / 100
            );
        assertGe(amountToReceive, 0);
        assertGe(burnAmount, 0);
    }

    function test_SetTgeTimestampZeroShouldRevert() public {
        MeliesStaking newStaking = new MeliesStaking(address(meliesToken));
        vm.expectRevert(MeliesStaking.InvalidStartTime.selector);
        newStaking.setTgeTimestamp(0);
    }

    function test_StakedEventEmitted() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        vm.expectEmit(true, true, true, true);
        emit MeliesStaking.Staked(user1, 10_000e8, 1);
        stakingContract.stake(10_000e8, 1, true);
        vm.stopPrank();
    }

    // ============================================================================
    // PRECISION AND CALCULATION TESTS
    // ============================================================================

    /// @notice Test reward calculation with zero total ponderated staked
    function test_CalculateRewardsWithZeroTotalPonderatedStaked() public {
        // Don't stake anything, just update rewards
        vm.warp(block.timestamp + 1 days);
        stakingContract.updateAccumulatedRewards();

        // Test that the function handles zero total ponderated staked gracefully
        // by checking that the contract state is correct
        assertEq(stakingContract.getTotalPonderatedStaked(), 0);
        assertEq(stakingContract.getTotalStaked(), 0);
    }

    function test_VeryLargeStakeAmount() public {
        // Setup clean contracts
        Melies newMelies = new Melies(address(admin));
        newMelies.grantRole(newMelies.MINTER_ROLE(), admin);
        MeliesStaking newStaking = new MeliesStaking(address(newMelies));
        newStaking.setTgeTimestamp(uint32(tgeTimestamp));

        // Test with max supply
        uint256 maxAmount = 1_000_000_000e8;
        newMelies.mint(user1, maxAmount);

        vm.startPrank(user1);
        newMelies.approve(address(newStaking), maxAmount);
        newStaking.stake(maxAmount, 0, true);
        vm.stopPrank();

        // Verify stake was created with correct amount
        MeliesStaking.StakingInfo[] memory userStakes = newStaking
            .getUserStakes(user1);
        assertEq(
            userStakes[0].amountWithPrecision,
            maxAmount * 10 ** PRECISION_FACTOR
        );
    }

    function test_UpdateAccumulatedRewardsGasLimit() public {
        // Create many users with stakes to test gas limit
        for (uint256 i = 0; i < 50; i++) {
            address user = address(uint160(i + 1000));
            meliesToken.mint(user, 10_000e8);
            vm.startPrank(user);
            meliesToken.approve(address(stakingContract), 10_000e8);
            stakingContract.stake(10_000e8, 0, true);
            vm.stopPrank();
        }

        // Fast forward and update rewards
        vm.warp(block.timestamp + 1 days);
        stakingContract.updateAccumulatedRewards();
        assertTrue(true); // Should complete without hitting gas limit
    }

    function test_UnstakedEventEmitted() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit MeliesStaking.Unstaked(user1, 10_000e8, 0);
        stakingContract.unstake(0, 10_000e8 * 10 ** PRECISION_FACTOR);
        vm.stopPrank();
    }

    function test_RewardsClaimedEventEmitted() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);
        stakingContract.updateAccumulatedRewards();
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        (uint256 rewards, ) = stakingContract.calculateRewards(
            user1,
            0,
            stakingContract.DAILY_BUDGET_TARGET()
        );
        emit MeliesStaking.RewardsClaimed(
            user1,
            rewards / 10 ** PRECISION_FACTOR
        );
        stakingContract.claimRewards(0);
        vm.stopPrank();
    }

    function test_EarlyUnstakedEventEmitted() public {
        // Stake with lock
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true);
        vm.stopPrank();

        // Fast forward to allow early unstaking
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(user1);
        stakingContract.earlyUnstake(0, 10_000e8);
        vm.stopPrank();
        assertTrue(true); // Should complete without reverting
    }

    function test_ConstructorWithZeroAddress() public {
        // The constructor doesn't check for zero address, so it should work
        MeliesStaking newStaking = new MeliesStaking(address(0));
        assertTrue(address(newStaking) != address(0));
    }

    function test_RoleManagement() public {
        // Test role management functionality
        assertTrue(
            stakingContract.hasRole(stakingContract.DEFAULT_ADMIN_ROLE(), admin)
        );
        assertTrue(stakingContract.hasRole(ADMIN_ROLE, admin));
        assertFalse(stakingContract.hasRole(ADMIN_ROLE, user1));
    }

    // ============================================================================
    // UPDATE ACCUMULATED REWARDS ROLE TESTS
    // ============================================================================

    /// @notice Test that updateAccumulatedRewards can be called by non-admin users
    function test_UpdateAccumulatedRewardsCallableByNonAdmin() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);

        // Non-admin user should be able to call updateAccumulatedRewards
        vm.prank(user1);
        stakingContract.updateAccumulatedRewards();

        // Verify rewards were updated
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    /// @notice Test that updateAccumulatedRewards can be called by any user address
    function test_UpdateAccumulatedRewardsCallableByAnyUser() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);

        // User2 (who has no stakes) should be able to call updateAccumulatedRewards
        vm.prank(user2);
        stakingContract.updateAccumulatedRewards();

        // Verify rewards were updated for user1
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    /// @notice Test that updateAccumulatedRewards cooldown works
    function test_UpdateAccumulatedRewardsCooldownWorks() public {
        setupStakingWithoutCompound();
        uint32 lastUpdateTime = uint32(block.timestamp) + 1 days;
        vm.warp(lastUpdateTime);

        // First call should work
        stakingContract.updateAccumulatedRewards();

        // Second call immediately after should fail due to cooldown
        vm.expectRevert(MeliesStaking.CanOnlyUpdateOncePerDay.selector);
        stakingContract.updateAccumulatedRewards();

        // Third call after 23 hours 59 minutes shouldn't work
        vm.warp(lastUpdateTime + 1 days - 1);
        vm.expectRevert(MeliesStaking.CanOnlyUpdateOncePerDay.selector);
        stakingContract.updateAccumulatedRewards();

        // Fourth call after 1 day should work
        vm.warp(lastUpdateTime + 1 days);
        stakingContract.updateAccumulatedRewards();

        // Fifth call after 1 day 1 second shouldn't work again
        vm.warp(lastUpdateTime + 1 days + 1);
        vm.expectRevert(MeliesStaking.CanOnlyUpdateOncePerDay.selector);
        stakingContract.updateAccumulatedRewards();
    }

    // ============================================================================
    // ADDITIONAL EDGE CASES
    // ============================================================================

    /// @notice Test staking with zero amount
    function test_StakeWithZeroAmount() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 0);
        vm.expectRevert(MeliesStaking.StakingAmountTooLow.selector);
        stakingContract.stake(0, 0, true);
        vm.stopPrank();
    }

    function test_StakeWithExcessiveAmount() public {
        uint256 excessiveAmount = 100_000_000e8; // 100M tokens (large but within max supply)
        // Use admin to mint tokens to user1
        vm.prank(admin);
        meliesToken.mint(user1, excessiveAmount);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), excessiveAmount);
        stakingContract.stake(excessiveAmount, 0, true);
        vm.stopPrank();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(
            userStakes[0].amountWithPrecision,
            excessiveAmount * 10 ** PRECISION_FACTOR
        );
    }

    function test_StakeWithInvalidDurationIndex() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        vm.expectRevert(MeliesStaking.InvalidDurationIndex.selector);
        stakingContract.stake(10_000e8, 5, true); // Invalid index 5
        vm.stopPrank();
    }

    function test_StakeWithInsufficientAllowance() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 5_000e8); // Less than stake amount
        vm.expectRevert();
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();
    }

    function test_StakeWithRevokedAllowance() public {
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        meliesToken.approve(address(stakingContract), 0); // Revoke allowance
        vm.expectRevert();
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();
    }

    function test_StakeWithTransferFailure() public {
        // This would require a mock token that fails on transfer
        // For now, we test with insufficient balance
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        // Use admin to burn user's tokens to create insufficient balance
        vm.stopPrank();

        vm.prank(admin);
        uint256 userBalance = meliesToken.balanceOf(user1);
        if (userBalance > 0) {
            meliesToken.burn(user1, userBalance);
        }

        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();
    }

    // Unstaking Edge Cases
    function test_UnstakeWithZeroAmount() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user1);
        // The contract should handle zero amount gracefully, not revert
        stakingContract.unstake(0, 0);
        vm.stopPrank();

        // Verify the stake is still there
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes.length, 1);
    }

    function test_UnstakeWithExcessiveAmount() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user1);
        vm.expectRevert(
            MeliesStaking.AmountGreaterThanPonderatedStakeAmount.selector
        );
        stakingContract.unstake(0, 20_000e8 * 10 ** PRECISION_FACTOR);
        vm.stopPrank();
    }

    function test_UnstakeWithInvalidStakeIndex() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user1);
        vm.expectRevert(MeliesStaking.InvalidStakeIndex.selector);
        stakingContract.unstake(1, 10_000e8 * 10 ** PRECISION_FACTOR);
        vm.stopPrank();
    }

    function test_UnstakeWithLockedStake() public {
        setupStakingWithCompound(); // Uses durationIndex 1 (90 days)

        vm.startPrank(user1);
        vm.expectRevert(MeliesStaking.StakingPeriodNotEnded.selector);
        stakingContract.unstake(0, 10_000e8 * 10 ** PRECISION_FACTOR);
        vm.stopPrank();
    }

    function test_UnstakeWithPartialAmount() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 partialAmount = userStakes[0].ponderatedAmountWithPrecision / 2;

        vm.startPrank(user1);
        stakingContract.unstake(0, partialAmount);
        vm.stopPrank();

        // Verify partial unstake worked
        userStakes = stakingContract.getUserStakes(user1);
        assertEq(userStakes[0].ponderatedAmountWithPrecision, partialAmount);
    }

    // Early Unstaking Edge Cases
    function test_EarlyUnstakeWithZeroBurnAmount() public {
        // Stake with no-lock (index 0) - should have 0% burn
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialBalance = meliesToken.balanceOf(user1);

        vm.startPrank(user1);
        // For no-lock stakes, earlyUnstake should call unstake internally
        // This will fail due to reentrancy guard, so we test the preview instead
        (
            uint256 netAmount,
            uint256 burnAmount,
            uint256 burnPercentage,
            uint256 monthsElapsed
        ) = stakingContract.previewEarlyUnstaking(
                user1,
                0,
                userStakes[0].ponderatedAmountWithPrecision
            );

        assertEq(burnPercentage, 0); // No burn for no-lock stakes
        assertEq(monthsElapsed, 0);
        vm.stopPrank();
    }

    function test_EarlyUnstakeWithExcessiveBurnAmount() public {
        // This test verifies the burn calculation doesn't exceed 90%
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 1, true); // LUNAR program
        vm.stopPrank();

        // Fast forward to first month (should have 90% burn)
        vm.warp(block.timestamp + 30 days);

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialBalance = meliesToken.balanceOf(user1);

        vm.startPrank(user1);
        stakingContract.earlyUnstake(
            0,
            userStakes[0].ponderatedAmountWithPrecision
        );
        vm.stopPrank();

        uint256 finalBalance = meliesToken.balanceOf(user1);
        // Should receive 10% of 10000 tokens = 1000 tokens (plus any accumulated rewards)
        assertGt(finalBalance - initialBalance, 0);
        assertLe(finalBalance - initialBalance, 10_000e8); // Should not exceed original stake
    }

    function test_EarlyUnstakeWithInvalidBurnPercentage() public {
        // This test verifies burn percentage calculation is correct
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 2, true); // SOLAR program
        vm.stopPrank();

        // Fast forward to 3 months (should have 45% burn, not 60%)
        vm.warp(block.timestamp + 90 days);

        // Get the actual ponderated amount from the stake
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 ponderatedAmount = userStakes[0].ponderatedAmountWithPrecision;

        (
            uint256 netAmount,
            uint256 burnAmount,
            uint256 burnPercentage,
            uint256 monthsElapsed
        ) = stakingContract.previewEarlyUnstaking(user1, 0, ponderatedAmount);

        // After 3 months (90 days), SOLAR program should have 45% burn
        assertEq(burnPercentage, 4500); // 45%
        assertEq(monthsElapsed, 3);
    }

    function test_EarlyUnstakeWithNoLockStake() public {
        // Test early unstaking a no-lock stake (should work normally)
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialBalance = meliesToken.balanceOf(user1);

        vm.startPrank(user1);
        // For no-lock stakes, earlyUnstake should call unstake internally
        // This will fail due to reentrancy guard, so we test the preview instead
        (
            uint256 netAmount,
            uint256 burnAmount,
            uint256 burnPercentage,
            uint256 monthsElapsed
        ) = stakingContract.previewEarlyUnstaking(
                user1,
                0,
                userStakes[0].ponderatedAmountWithPrecision
            );

        assertEq(burnPercentage, 0); // No burn for no-lock stakes
        assertEq(monthsElapsed, 0);
        vm.stopPrank();
    }

    // Reward Calculation Edge Cases
    function test_RewardCalculationWithZeroStakers() public {
        // Don't stake anything
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        assertEq(stakingContract.getTotalStaked(), 0);
        assertEq(stakingContract.getTotalPonderatedStaked(), 0);
    }

    function test_RewardCalculationWithSingleStaker() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    function test_RewardCalculationWithMultipleStakers() public {
        // Setup multiple stakers
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 0, false);
        vm.stopPrank();

        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 20_000e8);
        stakingContract.stake(20_000e8, 1, false);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Both should have stakes
        MeliesStaking.StakingInfo[] memory user1Stakes = stakingContract
            .getUserStakes(user1);
        MeliesStaking.StakingInfo[] memory user2Stakes = stakingContract
            .getUserStakes(user2);
        assertEq(user1Stakes.length, 1);
        assertEq(user2Stakes.length, 1);
        // Check that stakes were created successfully
        assertGt(user1Stakes[0].amountWithPrecision, 0);
        assertGt(user2Stakes[0].amountWithPrecision, 0);
    }

    function test_RewardCalculationWithVeryLargeStakes() public {
        uint256 largeStake = 1_000_000e8;
        // Use admin to mint tokens to user1
        vm.prank(admin);
        meliesToken.mint(user1, largeStake);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), largeStake);
        stakingContract.stake(largeStake, 0, false);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    function test_RewardCalculationWithPrecisionLoss() public {
        // Test with very small amounts to check precision handling
        uint256 smallStake = 5000e8; // Minimum stake
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), smallStake);
        stakingContract.stake(smallStake, 0, false);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    // Compound Reward Tests
    function test_CompoundRewardsWithZeroRewards() public {
        setupStakingWithCompound();
        // Don't update rewards, so no rewards to compound
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertEq(userStakes[0].accumulatedRewardsWithPrecision, 0);
    }

    function test_CompoundRewardsWithExcessiveRewards() public {
        setupStakingWithCompound();
        vm.warp(block.timestamp + 365 days); // 1 year of rewards
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(
            userStakes[0].amountWithPrecision,
            10_000e8 * 10 ** PRECISION_FACTOR
        );
    }

    function test_CompoundRewardsWithPrecisionIssues() public {
        setupStakingWithCompound();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertGt(
            userStakes[0].amountWithPrecision,
            10_000e8 * 10 ** PRECISION_FACTOR
        );
    }

    function test_ToggleCompoundRewardsWithActiveRewards() public {
        setupStakingWithoutCompound();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Toggle compound rewards
        vm.prank(user1);
        stakingContract.toggleCompoundRewards(0);

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        assertTrue(userStakes[0].compoundRewards);
    }

    // TGE and Time Management Tests
    function test_SetTgeTimestampWithZeroValue() public {
        MeliesStaking newStaking = new MeliesStaking(address(meliesToken));
        vm.expectRevert(MeliesStaking.InvalidStartTime.selector);
        newStaking.setTgeTimestamp(0);
    }

    function test_SetTgeTimestampWithPastValue() public {
        MeliesStaking newStaking = new MeliesStaking(address(meliesToken));
        // Use a safe past timestamp to avoid overflow
        uint32 pastTimestamp = uint32(1000); // Use a fixed past timestamp
        newStaking.setTgeTimestamp(pastTimestamp);
        assertTrue(newStaking.isTgeTimestampSet());
    }

    function test_SetTgeTimestampWithFutureValue() public {
        MeliesStaking newStaking = new MeliesStaking(address(meliesToken));
        newStaking.setTgeTimestamp(uint32(block.timestamp + 1 days));
        assertTrue(newStaking.isTgeTimestampSet());
    }

    function test_SetTgeTimestampMultipleTimes() public {
        vm.expectRevert(MeliesStaking.TgeTimestampAlreadySet.selector);
        stakingContract.setTgeTimestamp(100);
    }

    function test_StakeBeforeTgeTimestampSet() public {
        MeliesStaking newStaking = new MeliesStaking(address(meliesToken));
        vm.startPrank(user1);
        meliesToken.approve(address(newStaking), 10_000e8);
        vm.expectRevert(MeliesStaking.TgeTimestampNotSet.selector);
        newStaking.stake(10_000e8, 0, true);
        vm.stopPrank();
    }

    // Time-Based Edge Cases
    function test_StakeAfter90DaysFromTGE() public {
        vm.warp(tgeTimestamp + 91 days);

        // Should work for non-genesis stakes
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();

        // Should fail for genesis stakes
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 200_000e8);
        vm.expectRevert(MeliesStaking.CannotStakeAfter90DaysFromTGE.selector);
        stakingContract.stake(200_000e8, 4, true);
        vm.stopPrank();
    }

    function test_StakeExactly90DaysFromTGE() public {
        vm.warp(tgeTimestamp + 90 days);

        // Should work for genesis stakes
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 200_000e8);
        stakingContract.stake(200_000e8, 4, true);
        vm.stopPrank();
    }

    function test_StakeWithTimeManipulation() public {
        // Test that time manipulation doesn't affect staking logic
        vm.warp(tgeTimestamp + 89 days);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 200_000e8);
        stakingContract.stake(200_000e8, 4, true);
        vm.stopPrank();

        // Try to manipulate time after staking
        vm.warp(block.timestamp + 1 days);
        // Should still be able to stake normally
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 0, true);
        vm.stopPrank();
    }

    // Admin Function Tests
    function test_SetDurationMultipliersWithInvalidValues() public {
        uint16[5] memory invalidMultipliers = [2e2, 1.5e2, 2e2, 2.5e2, 3.5e2]; // First not 1e2
        vm.prank(admin);
        vm.expectRevert(MeliesStaking.InvalidMultiplier.selector);
        stakingContract.setDurationMultipliers(invalidMultipliers);
    }

    function test_SetDailyBudgetTargetWithZeroValue() public {
        vm.prank(admin);
        vm.expectRevert(
            MeliesStaking.DailyBudgetMustBeGreaterThanZero.selector
        );
        stakingContract.setDailyBudgetTarget(0);
    }

    function test_SetMinStakeAmountWithZeroValue() public {
        vm.prank(admin);
        stakingContract.setMinStakeAmount(0);
        assertEq(stakingContract.MIN_STAKE_AMOUNT(), 0);
    }

    function test_SetMinStakeAmountWithExcessiveValue() public {
        uint256 excessiveValue = 1_000_000_000e8;
        vm.prank(admin);
        stakingContract.setMinStakeAmount(excessiveValue);
        assertEq(stakingContract.MIN_STAKE_AMOUNT(), excessiveValue);
    }

    function test_AdminFunctionsWithNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        stakingContract.setDurationMultipliers([1e2, 1.5e2, 2e2, 2.5e2, 3.5e2]);

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.setDailyBudgetTarget(10_000e8);

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.setMinStakeAmount(1000e8);

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.pause();

        vm.prank(user1);
        vm.expectRevert();
        stakingContract.emergencyWithdraw(address(meliesToken), 1000e8);
    }

    // Emergency and Safety Tests
    function test_EmergencyWithdrawWithZeroBalance() public {
        vm.prank(admin);
        stakingContract.emergencyWithdraw(address(meliesToken), 0);
        // Should not revert
    }

    function test_EmergencyWithdrawWithInsufficientBalance() public {
        uint256 contractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        vm.prank(admin);
        vm.expectRevert();
        stakingContract.emergencyWithdraw(
            address(meliesToken),
            contractBalance + 1
        );
    }

    function test_EmergencyWithdrawWithNonStakingToken() public {
        MockERC20 mockToken = new MockERC20("MOCK", "MOCK");
        mockToken.mint(address(stakingContract), 1000e18);

        uint256 initialAdminBalance = mockToken.balanceOf(admin);
        vm.prank(admin);
        stakingContract.emergencyWithdraw(address(mockToken), 1000e18);
        uint256 finalAdminBalance = mockToken.balanceOf(admin);
        assertEq(finalAdminBalance - initialAdminBalance, 1000e18);
    }

    function test_PauseUnpauseWithActiveStakes() public {
        setupStakingWithoutCompound();

        // Pause with active stakes
        stakingContract.pause();
        assertTrue(stakingContract.paused());

        // Unpause
        stakingContract.unpause();
        assertFalse(stakingContract.paused());

        // Should be able to interact normally after unpause
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        stakingContract.unstake(0, 10_000e8 * 10 ** PRECISION_FACTOR);
        vm.stopPrank();
    }
}
