// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/mock/MockMelies.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract MeliesStakingTest is Test {
    DebugMeliesStaking public stakingContract;
    Melies public meliesToken;
    uint256 public tgeTimestamp;

    address public admin;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    mapping(string => address) private userAddresses;
    uint256 private nextUserIndex = 5;

    uint256 private constant ANNUAL_BUDGET = 2_280_000e8; // 2.28M tokens
    uint256 private constant DAILY_BUDGET =
        (ANNUAL_BUDGET / 365) * 10 ** PRECISION_FACTOR;
    uint256 private constant PRECISION_FACTOR = 12;
    uint256 private constant DURATION_MULTIPLIER_PRECISION = 2;
    uint256[5] private DURATION_MULTIPLIERS = [1e2, 1.3e2, 1.6e2, 2.2e2, 3e2];

    bytes4 private constant ENFORCED_PAUSE_SELECTOR =
        bytes4(keccak256("EnforcedPause()"));

    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Add these custom error definitions at the top of the contract
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

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        user4 = address(0x4);
        userAddresses["user1"] = user1;
        userAddresses["user2"] = user2;
        userAddresses["user3"] = user3;
        userAddresses["user4"] = user4;

        tgeTimestamp = 1;

        // Deploy Melies token
        meliesToken = new Melies(admin, tgeTimestamp);

        // Deploy MeliesStaking contract
        stakingContract = new DebugMeliesStaking(
            address(meliesToken),
            uint32(tgeTimestamp)
        );

        // Grant MINTER_ROLE to admin for initial token distribution
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), admin);

        // Transfer 100M tokens to staking contract
        meliesToken.mint(address(stakingContract), 100_000_000 * 1e8);

        // Distribute tokens to users
        meliesToken.mint(user1, 100_000e8);
        meliesToken.mint(user2, 100_000e8);
        meliesToken.mint(user3, 100_000e8);
        meliesToken.mint(user4, 100_000e8);

        // Grant ADMIN_ROLE to admin in staking contract
        stakingContract.grantRole(ADMIN_ROLE, admin);
    }

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

    function test_Unstake() public {
        setupStakingWithoutCompound();

        setupRewards(20);

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].amountWithPrecision);

        assertEq(stakingContract.getTotalPonderatedStaked(), 0);
        assertEq(stakingContract.getTotalStaked(), 0);
    }

    function test_PartialUnstake() public {
        // Setup initial stake
        setupStakingWithCompound();

        // Fast forward 31 days to allow unstaking
        vm.warp(block.timestamp + 91 days);

        // Update accumulated rewards
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Get initial balances and stake info
        uint256 initialUserBalance = meliesToken.balanceOf(user1);
        uint256 initialContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialStakeAmount = userStakes[0].amountWithPrecision;
        uint256 initialPonderatedAmount = userStakes[0]
            .ponderatedAmountWithPrecision;

        // Calculate 50% of the staked amount
        uint256 unstakeAmount = initialPonderatedAmount / 2;

        // Perform partial unstake
        vm.prank(user1);
        stakingContract.unstake(0, unstakeAmount);

        // Check updated balances and stake info
        uint256 finalUserBalance = meliesToken.balanceOf(user1);
        uint256 finalContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        userStakes = stakingContract.getUserStakes(user1);

        // Assert that 50% of the stake was unstaked
        assertEq(
            userStakes[0].ponderatedAmountWithPrecision,
            initialPonderatedAmount - unstakeAmount
        );
        assertEq(userStakes[0].amountWithPrecision, initialStakeAmount / 2);

        // Assert that the user received the unstaked amount plus rewards
        uint256 unstakeAmountWithRewards = finalUserBalance -
            initialUserBalance;

        // Assert that the contract balance decreased by the unstaked amount
        assertEq(
            initialContractBalance - finalContractBalance,
            unstakeAmountWithRewards
        );

        // Assert that the total staked and ponderated staked amounts were updated correctly
        assertEq(
            stakingContract.getTotalStaked(),
            initialStakeAmount / 2 / 10 ** PRECISION_FACTOR
        );
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            (initialPonderatedAmount - unstakeAmount) / 10 ** PRECISION_FACTOR
        );
    }

    function test_GenesisStakingWithin90DaysAfterTGE() public {
        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 4; // 365 days
        bool compoundRewards = true;

        // Set the current time to 89 days after TGE
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
        uint256 stakeAmount = 10_000 * 1e8;
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
        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 4; // 365 days
        bool compoundRewards = true;

        // Set the current time to 91 days after TGE
        vm.warp(tgeTimestamp + 91 days);

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        vm.expectRevert(CannotStakeAfter90DaysFromTGE.selector);
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

    function test_UpdateAccumulatedRewardsNoCompound() public {
        uint256 stakeAmount = 10_000 * 1e8;
        uint8 durationIndex = 0;
        bool compoundRewards = false;

        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, durationIndex, compoundRewards);
        vm.stopPrank();

        // Fast forward 1 day
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

    function test_IsRewardUpdatingTests() public {
        vm.pauseGasMetering();
        vm.warp(1);
        uint256 numStakers = 40_000;

        // Setup multiple stakes
        for (uint256 i = 0; i < numStakers; i++) {
            address staker = address(uint160(i + 1));
            meliesToken.mint(staker, 100e8);
            vm.startPrank(staker);
            meliesToken.approve(address(stakingContract), 100e8);
            stakingContract.stake(100e8, 4, true);
            vm.stopPrank();
        }

        // Fast forward 1 day
        vm.warp(1 + 1 days);

        // Start updating rewards
        vm.resumeGasMetering();
        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();
        vm.resetGasMetering();

        // isRewardUpdating should be true
        assertTrue(stakingContract.isRewardUpdating());

        // Attempt to stake while rewards are updating
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 20_000e8);
        vm.expectRevert(RewardsBeingUpdated.selector);
        stakingContract.stake(20_000e8, 2, true);
        vm.stopPrank();

        // Attempt to unstake while rewards are updating
        vm.prank(address(uint160(1)));
        vm.expectRevert(RewardsBeingUpdated.selector);
        stakingContract.unstake(0, 50e8);

        // Process remaining stakes
        while (stakingContract.isRewardUpdating()) {
            vm.resetGasMetering();
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }
        vm.resetGasMetering();

        // After processing all stakes, isRewardUpdating should be false
        assertFalse(stakingContract.isRewardUpdating());

        // Now staking and unstaking should work
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 20_000e8);
        stakingContract.stake(20_000e8, 2, true);
        vm.stopPrank();

        // Fast forward 1 year for unstaking
        vm.warp(1 + 366 days);

        vm.prank(address(uint160(1)));
        stakingContract.unstake(0, 50e8);
    }

    function test_EmergencyWithdraw() public {
        uint256 stakeAmount = 10_000 * 1e8;

        setupStakingWithCompound();

        uint256 initialAdminBalance = meliesToken.balanceOf(admin);
        uint256 initialContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        assertEq(initialContractBalance, 100_000_000 * 1e8 + stakeAmount);

        stakingContract.emergencyWithdraw(
            address(meliesToken),
            100_000_000 * 1e8 + stakeAmount
        );

        uint256 finalContractBalance = meliesToken.balanceOf(
            address(stakingContract)
        );
        assertEq(finalContractBalance, 0);

        uint256 adminBalance = meliesToken.balanceOf(admin);
        assertEq(
            adminBalance,
            100_000_000 * 1e8 + stakeAmount - initialAdminBalance
        );
    }

    // cf results of python_script/staking_scenario1.py
    function test_MultipleStakingScenario1() public {
        uint256 dayCounter = 0;
        uint256 startTime = 1 + 1 days;
        uint16 i;

        uint256 balanceBefore = meliesToken.balanceOf(address(stakingContract));

        // Day 1: Bob stakes 1000 tokens with 180 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 1000e8);
        stakingContract.stake(1000e8, 2, true); // 180 days, compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Day 2: Alice stakes 100 tokens with no lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 100e8);
        stakingContract.stake(100e8, 0, false); // No lock, no compound
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

        // Day 5: Bob stakes another 1000 tokens with 90 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 1000e8);
        stakingContract.stake(1000e8, 1, true); // 90 days, compound
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

        // Day 10: Charlie stakes 10000 tokens with 365 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user3);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 4, true); // 365 days, compound
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

        // Day 23: Alice unstakes her 100 tokens
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialUserBalance = meliesToken.balanceOf(user1);

        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        uint256 finalUserBalance = meliesToken.balanceOf(user1);
        assertEq(finalUserBalance - initialUserBalance, 29_852_930_578); //  10,000,000,000 + 19,852,930,578 = 29_852_930_578

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
        assertEq(finalUserBalance - initialUserBalance, 804_149_589_442);

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
        meliesToken.approve(address(stakingContract), 1_000e8);
        stakingContract.stake(1_000e8, 3, true); // 365 days, compound
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
        assertEq(finalUserBalance - initialUserBalance, 54_513_087_982_883);

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
            212_537_270_763_549
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
            961_830_110_494_007
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
            2_085_875_558_656_613
        );
        userStakes = stakingContract.getUserStakes(user1);
        assertEq(
            userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR,
            975_366_400_339
        );
        userStakes = stakingContract.getUserStakes(user3);
        assertEq(
            userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR,
            694_576_584_191_955
        );

        userStakes = stakingContract.getUserStakes(user1);
        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        userStakes = stakingContract.getUserStakes(user3);
        vm.prank(user3);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        assertEq(stakingContract.getTotalPonderatedStaked(), 0);

        uint256 balanceAfter = meliesToken.balanceOf(address(stakingContract));
        uint256 diff = balanceBefore - balanceAfter;
        assertApproxEqAbs((diff * 10) / (ANNUAL_BUDGET / 365), 1200 * 10, 1);
    }

    // cf results of python_script/staking_scenario2.py
    function test_MultipleStakingScenario2() public {
        uint256 dayCounter = 0;
        uint256 startTime = 1 + 1 days;
        uint16 i;

        uint256 balanceBefore = meliesToken.balanceOf(address(stakingContract));

        // Day 1: Bob stakes 1000 tokens with 180 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 1000e8);
        stakingContract.stake(1000e8, 2, true); // 180 days, compound
        vm.stopPrank();

        vm.prank(admin);
        stakingContract.updateAccumulatedRewards();

        // Day 2: Alice stakes 100 tokens with no lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user1);
        meliesToken.approve(address(stakingContract), 100e8);
        stakingContract.stake(100e8, 0, false); // No lock, no compound
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

        // Day 5: Bob stakes another 1000 tokens with 90 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user2);
        meliesToken.approve(address(stakingContract), 1000e8);
        stakingContract.stake(1000e8, 1, true); // 90 days, compound
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

        // Day 10: Charlie stakes 10000 tokens with 365 days lock
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;
        vm.startPrank(user3);
        meliesToken.approve(address(stakingContract), 10_000e8);
        stakingContract.stake(10_000e8, 4, true); // 365 days, compound
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

        // Day 23: Alice unstakes her 100 tokens
        vm.warp(startTime + dayCounter * 1 days);
        dayCounter++;

        MeliesStaking.StakingInfo[] memory userStakes = stakingContract
            .getUserStakes(user1);
        uint256 initialUserBalance = meliesToken.balanceOf(user1);

        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        uint256 finalUserBalance = meliesToken.balanceOf(user1);
        assertEq(finalUserBalance - initialUserBalance, 29_852_930_578); //  10,000,000,000 + 19,852,930,578 = 29_852_930_578

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

        initialUserBalance = meliesToken.balanceOf(user2);
        uint256 unstakeAmount = 804_149_589_441 *
            DURATION_MULTIPLIERS[1] *
            10 ** (PRECISION_FACTOR - DURATION_MULTIPLIER_PRECISION);

        vm.prank(user2);
        stakingContract.unstake(1, unstakeAmount);

        finalUserBalance = meliesToken.balanceOf(user2);
        assertEq(finalUserBalance - initialUserBalance, 804_149_589_441);

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
        meliesToken.approve(address(stakingContract), 1_000e8);
        stakingContract.stake(1_000e8, 3, true); // 365 days, compound
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

        initialUserBalance = meliesToken.balanceOf(user2);
        unstakeAmount =
            54_513_087_982_882 *
            DURATION_MULTIPLIERS[2] *
            10 ** (PRECISION_FACTOR - DURATION_MULTIPLIER_PRECISION);

        vm.prank(user2);
        stakingContract.unstake(0, unstakeAmount);

        finalUserBalance = meliesToken.balanceOf(user2);
        assertEq(finalUserBalance - initialUserBalance, 54_513_087_982_882);

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
            212_537_270_763_553
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
            961_830_110_494_004
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
            2_085_875_558_656_603
        );

        userStakes = stakingContract.getUserStakes(user1);
        assertEq(
            userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR,
            975_366_400_339
        );

        userStakes = stakingContract.getUserStakes(user2);
        assertEq(userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR, 5);
        assertEq(userStakes[1].amountWithPrecision / 10 ** PRECISION_FACTOR, 7);

        userStakes = stakingContract.getUserStakes(user3);
        assertEq(
            userStakes[0].amountWithPrecision / 10 ** PRECISION_FACTOR,
            694_576_584_191_946
        );

        userStakes = stakingContract.getUserStakes(user1);
        vm.prank(user1);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        userStakes = stakingContract.getUserStakes(user2);
        vm.startPrank(user2);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);
        stakingContract.unstake(0, userStakes[1].ponderatedAmountWithPrecision);
        vm.stopPrank();

        userStakes = stakingContract.getUserStakes(user3);
        vm.prank(user3);
        stakingContract.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        assertEq(stakingContract.getTotalPonderatedStaked(), 0);

        uint256 balanceAfter = meliesToken.balanceOf(address(stakingContract));
        uint256 diff = balanceBefore - balanceAfter;
        assertApproxEqAbs((diff * 10) / (ANNUAL_BUDGET / 365), 1200 * 10, 1);
    }

    function test_GasConsumptionDailyCalculation() public {
        vm.pauseGasMetering();
        uint256 dayCounter = 0;
        uint256 startTime = 1 + 1 days;
        uint256 i;
        uint256 numStakers = 500_000; // 50_000_000 (estimated max supply for staking) / 100 (min staking) = 500_000 stakers

        // Stake for each simulated user
        for (i = 0; i < numStakers; i++) {
            address staker = address(uint160(i + 1));
            meliesToken.mint(staker, 100e8);
            vm.startPrank(staker);
            meliesToken.approve(address(stakingContract), 100e8);
            stakingContract.stake(100e8, 4, true);
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
            stakingContract.updateAccumulatedRewards{gas: 156_000_000}();
            gasAfter = gasleft();
            gasUsed = gasBefore - gasAfter;
            // Assert that gas usage is within an acceptable range even with a large number of stakers
            // In Base chain, block gas limit is still growing. For now, it's 156M
            assert(gasUsed < 156_000_000);
            vm.resetGasMetering();
        } while (stakingContract.isRewardUpdating());

        // Check results
        assertEq(
            stakingContract.getTotalPonderatedStaked(),
            500_000 * 100e8 * 3 + ((ANNUAL_BUDGET / 365) * 3) // 500_000 * 1e8 * 3 + Daily budget * 3
        );
    }

    // It needs to be runs with a large gas-limit because vm.pauseGasMetering() is bugged aud cause memoryOOG error
    function test_LargeAmountStakersScenario() public {
        uint256 startTime = 1 + 1 days;
        uint256 simulationDuration = 1200; // ~39 months

        string[] memory inputs = new string[](6);
        inputs[0] = "python";
        inputs[1] = "python_script/staking_sim.py";
        inputs[2] = Strings.toString(15000); //  15000 users
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
                stakingContract.updateAccumulatedRewards();
                currentDay++;
            }

            if (
                keccak256(abi.encodePacked(actionType)) ==
                keccak256(abi.encodePacked("stake"))
            ) {
                vm.startPrank(user);
                meliesToken.approve(address(stakingContract), amount);
                stakingContract.stake(amount, index, false);
                vm.stopPrank();
            } else if (
                keccak256(abi.encodePacked(actionType)) ==
                keccak256(abi.encodePacked("unstake"))
            ) {
                MeliesStaking.StakingInfo[] memory userStakes = stakingContract
                    .getUserStakes(user);
                if (userStakes.length > index) {
                    vm.prank(user);
                    stakingContract.unstake(
                        index,
                        userStakes[index].ponderatedAmountWithPrecision
                    );
                }
            }

            if (day > currentDay) {
                // update rewards after action
                vm.warp(startTime + currentDay * 1 days);
                vm.prank(admin);
                stakingContract.updateAccumulatedRewards();
                currentDay++;
            }
        }

        // Ensure we've updated rewards for all days in the simulation
        while (currentDay <= simulationDuration) {
            vm.warp(startTime + currentDay * 1 days);
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
            currentDay++;
        }

        uint256 actualPonderatedStake = stakingContract
            .getTotalPonderatedStaked();
        assertApproxEqAbs(actualPonderatedStake, expectedPonderatedStake, 1);
    }

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

            // Mint some tokens for the new user
            meliesToken.mint(newAddress, 1_000e8); // 100_000_000 / 1_000 = 100_000 loop possible
        }
        return userAddresses[user];
    }

    function split(
        string memory str,
        string memory delim
    ) internal pure returns (string[] memory) {
        uint count = 1;
        for (uint i = 0; i < bytes(str).length; i++) {
            if (
                keccak256(abi.encodePacked(bytes1(bytes(str)[i]))) ==
                keccak256(abi.encodePacked(bytes(delim)))
            ) {
                count++;
            }
        }

        string[] memory parts = new string[](count);
        count = 0;
        uint lastIndex = 0;
        for (uint i = 0; i < bytes(str).length; i++) {
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
        uint startIndex,
        uint endIndex
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function parseUint(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        uint256 result = 0;
        for (uint i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }

    // Helper function

    function setupStakingWithoutCompound() public {
        uint128 stakeAmount = 10_000e8;
        uint8 durationIndex = 0; // 90 days
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

    function setupRewards(uint _days) public {
        uint256 startTime = 1;
        for (uint256 i = 0; i < _days; i++) {
            startTime = startTime + 1 days;
            vm.warp(startTime);
            vm.prank(admin);
            stakingContract.updateAccumulatedRewards();
        }
    }
}
