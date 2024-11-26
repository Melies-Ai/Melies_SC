// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Melies.sol";
import "../src/MeliesStaking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract MeliesVotingPowerTest is Test {
    Melies public meliesToken;
    MeliesStaking public meliesStaking;
    address public admin;
    address public pauser;
    address public minter;
    address public burner;
    address public user1;
    address public user2;
    address public staker1;
    address public staker2;

    uint256 public constant TGE_TIMESTAMP = 1640995200; // January 1, 2022, 00:00:00 UTC
    uint256 public constant ANNUAL_BUDGET = 2_280_000e8; // 2.28M tokens
    uint256 public constant DAILY_BUDGET_TARGET = (ANNUAL_BUDGET / 365);

    function setUp() public {
        admin = address(this);
        pauser = address(0x1);
        minter = address(0x2);
        burner = address(0x3);
        user1 = address(0x4);
        user2 = address(0x5);
        staker1 = address(0x6);
        staker2 = address(0x7);

        meliesToken = new Melies(admin);
        meliesStaking = new MeliesStaking(
            address(meliesToken),
            uint32(TGE_TIMESTAMP)
        );

        vm.startPrank(admin);
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), pauser);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), minter);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), burner);
        meliesToken.grantRole(
            meliesToken.STAKER_CONTRACT_ROLE(),
            address(meliesStaking)
        );
        meliesToken.setStakingContract(address(meliesStaking));
        vm.stopPrank();

        vm.prank(minter);
        meliesToken.mint(address(meliesStaking), 100_000e8);
    }

    function test_InitialVotingPower() public {
        assertEq(
            meliesToken.getVotes(user1),
            0,
            "Initial voting power should be 0"
        );
    }

    function test_VotingPowerFromBalance() public {
        // Mint tokens to user1
        vm.prank(minter);
        meliesToken.mint(user1, 1000e8);

        // User needs to delegate to themselves to activate voting power
        vm.prank(user1);
        meliesToken.delegate(user1);

        assertEq(
            meliesToken.getVotes(user1),
            1000e8,
            "Voting power should equal balance after delegation"
        );
    }

    function test_VotingPowerWithStaking() public {
        // Mint tokens to staker1
        vm.prank(minter);
        meliesToken.mint(staker1, 1000e8);

        // Approve and stake tokens
        vm.startPrank(staker1);
        meliesToken.approve(address(meliesStaking), 500e8);
        meliesStaking.stake(500e8, 0, true); // No lock period, compound rewards enabled
        meliesToken.delegate(staker1);
        vm.stopPrank();

        // Should include both staked and unstaked balance
        assertEq(
            meliesToken.getVotes(staker1),
            1000e8,
            "Voting power should include staked tokens"
        );
    }

    function test_VotingPowerWithStakingAfterDelegation() public {
        // Mint tokens to staker1
        vm.prank(minter);
        meliesToken.mint(staker1, 1000e8);

        // Approve and stake tokens
        vm.startPrank(staker1);
        meliesToken.delegate(staker1);
        meliesToken.approve(address(meliesStaking), 500e8);
        meliesStaking.stake(500e8, 0, true); // No lock period, compound rewards enabled
        vm.stopPrank();

        // Should include both staked and unstaked balance
        assertEq(
            meliesToken.getVotes(staker1),
            1000e8,
            "Voting power should include staked tokens"
        );
    }

    function test_VotingPowerWithMultipleStakes() public {
        // Mint tokens to staker1
        vm.prank(minter);
        meliesToken.mint(staker1, 2000e8);

        // Create multiple stakes with different lock periods
        vm.startPrank(staker1);
        meliesToken.approve(address(meliesStaking), 2000e8);

        meliesStaking.stake(500e8, 0, true); // No lock
        meliesStaking.stake(500e8, 1, true); // 30 days lock
        meliesStaking.stake(500e8, 2, true); // 90 days lock

        meliesToken.delegate(staker1);
        vm.stopPrank();

        assertEq(
            meliesToken.getVotes(staker1),
            2000e8,
            "Voting power should include all staked tokens"
        );
    }

    function test_VotingPowerAfterTransfer() public {
        // Mint tokens to user1
        vm.prank(minter);
        meliesToken.mint(user1, 1000e8);

        // User1 delegates to themselves and stakes some tokens
        vm.startPrank(user1);
        meliesToken.approve(address(meliesStaking), 400e8);
        meliesStaking.stake(400e8, 0, true);
        meliesToken.delegate(user1);
        vm.stopPrank();

        // Transfer unstaked tokens to user2
        vm.prank(user1);
        meliesToken.transfer(user2, 500e8);

        // User2 delegates to themselves
        vm.prank(user2);
        meliesToken.delegate(user2);

        assertEq(
            meliesToken.getVotes(user1),
            500e8,
            "User1's voting power should include staked tokens + untransferred tokens"
        );
        assertEq(
            meliesToken.getVotes(user2),
            500e8,
            "User2's voting power should reflect transferred tokens"
        );
    }

    function test_VotingPowerWithDelegation() public {
        // Mint tokens to both users
        vm.startPrank(minter);
        meliesToken.mint(staker1, 1000e8);
        meliesToken.mint(staker2, 1000e8);
        vm.stopPrank();

        // Staker1 stakes tokens and delegates to staker2
        vm.startPrank(staker1);
        meliesToken.approve(address(meliesStaking), 600e8);
        meliesStaking.stake(600e8, 0, true);
        meliesToken.delegate(staker2);
        vm.stopPrank();

        // Staker2 stakes tokens and delegates to themselves
        vm.startPrank(staker2);
        meliesToken.approve(address(meliesStaking), 800e8);
        meliesStaking.stake(800e8, 1, true);
        meliesToken.delegate(staker2);
        vm.stopPrank();

        assertEq(
            meliesToken.getVotes(staker1),
            0,
            "Staker1 should have delegated all voting power"
        );
        assertEq(
            meliesToken.getVotes(staker2),
            2000e8,
            "Staker2 should have combined voting power including stakes"
        );
    }

    function test_VotingPowerWithUnstaking() public {
        // Mint tokens to staker
        vm.prank(minter);
        meliesToken.mint(staker1, 1000e8);

        // Stake tokens
        vm.startPrank(staker1);
        meliesToken.approve(address(meliesStaking), 800e8);
        meliesStaking.stake(800e8, 0, true);
        vm.stopPrank();

        // Fast forward past any lock period
        vm.warp(block.timestamp + 400 days);

        // Unstake tokens
        MeliesStaking.StakingInfo[] memory userStakes = meliesStaking
            .getUserStakes(staker1);
        vm.startPrank(staker1);
        meliesStaking.unstake(0, userStakes[0].ponderatedAmountWithPrecision);
        meliesToken.delegate(staker1);
        vm.stopPrank();

        assertEq(
            meliesToken.getVotes(staker1),
            1000e8,
            "Voting power should reflect unstaked tokens"
        );
    }

    function test_VotingPowerAfterMultipleStakes() public {
        // Initial setup
        vm.prank(minter);
        meliesToken.mint(staker1, 5000e8);
        vm.prank(staker1);
        meliesToken.delegate(staker1);

        // Check initial voting power after delegation
        assertEq(
            meliesToken.getVotes(staker1),
            5000e8,
            "Initial voting power incorrect"
        );

        // Create multiple stakes
        vm.startPrank(staker1);
        meliesToken.approve(address(meliesStaking), 4000e8);
        meliesStaking.stake(1000e8, 0, true); // No lock
        meliesStaking.stake(1000e8, 1, false); // 30 days lock
        meliesStaking.stake(2000e8, 2, true); // 90 days lock
        vm.stopPrank();

        assertEq(
            meliesToken.getVotes(staker1),
            5000e8,
            "Voting power should remain same after staking"
        );

        // Fast forward 1 days and update rewards
        vm.warp(block.timestamp + 1 days);
        meliesStaking.updateAccumulatedRewards();

        uint256 totalStaked = meliesStaking.getTotalUserStakes(staker1);

        // Check voting power after rewards update
        assertEq(meliesToken.getVotes(staker1), 1000e8 + totalStaked);

        MeliesStaking.StakingInfo[] memory userStakes = meliesStaking
            .getUserStakes(staker1);
        // Unstake from first position (no lock)
        vm.prank(staker1);
        meliesStaking.unstake(0, userStakes[0].ponderatedAmountWithPrecision);

        assertEq(
            meliesToken.getVotes(staker1),
            1000e8 + totalStaked,
            "Voting power should remain same after partial unstake"
        );
    }

    function test_VotingPowerAfterMultipleStakers() public {
        // Setup two stakers
        vm.startPrank(minter);
        meliesToken.mint(staker1, 3000e8);
        meliesToken.mint(staker2, 2000e8);
        vm.stopPrank();

        // Initial delegations
        vm.prank(staker1);
        meliesToken.delegate(staker2);
        vm.prank(staker2);
        meliesToken.delegate(staker2);

        assertEq(
            meliesToken.getVotes(staker2),
            5000e8,
            "Initial combined voting power incorrect"
        );

        // Staker1 creates multiple stakes
        vm.startPrank(staker1);
        meliesToken.approve(address(meliesStaking), 2500e8);
        meliesStaking.stake(1000e8, 0, true); // No lock
        meliesStaking.stake(1500e8, 2, false); // 180 days lock
        vm.stopPrank();

        // Staker2 creates a stake
        vm.startPrank(staker2);
        meliesToken.approve(address(meliesStaking), 1500e8);
        meliesStaking.stake(1500e8, 1, true); // 90 days lock
        vm.stopPrank();

        assertEq(
            meliesToken.getVotes(staker2),
            5000e8,
            "Voting power should remain same after all stakes"
        );

        // Fast forward 1 days and update rewards
        vm.warp(block.timestamp + 1 days);
        meliesStaking.updateAccumulatedRewards();

        uint256 totalStaked1 = meliesStaking.getTotalUserStakes(staker1);
        uint256 totalStaked2 = meliesStaking.getTotalUserStakes(staker2);

        // Check voting power after rewards update
        assertEq(
            meliesToken.getVotes(staker2),
            1000e8 + totalStaked1 + totalStaked2,
            "Voting power incorrect after rewards update"
        );

        // Staker1 changes delegation to self
        vm.prank(staker1);
        meliesToken.delegate(staker1);

        assertEq(
            meliesToken.getVotes(staker1),
            500e8 + totalStaked1,
            "Staker1 voting power incorrect after delegation change"
        );
        assertEq(
            meliesToken.getVotes(staker2),
            500e8 + totalStaked2,
            "Staker2 voting power incorrect after delegation change"
        );

        // Unstake all positions
        vm.warp(block.timestamp + 181 days);
        MeliesStaking.StakingInfo[] memory userStakes1 = meliesStaking
            .getUserStakes(staker1);
        MeliesStaking.StakingInfo[] memory userStakes2 = meliesStaking
            .getUserStakes(staker2);

        vm.startPrank(staker1);
        meliesStaking.unstake(0, userStakes1[0].amountWithPrecision);
        meliesStaking.unstake(0, userStakes1[1].amountWithPrecision);
        vm.stopPrank();

        vm.startPrank(staker2);
        meliesStaking.unstake(0, userStakes2[0].amountWithPrecision);
        vm.stopPrank();

        assertEq(
            meliesToken.getVotes(staker1),
            500e8 + totalStaked1,
            "Final staker1 voting power incorrect"
        );
        assertEq(
            meliesToken.getVotes(staker2),
            500e8 + totalStaked2,
            "Final staker2 voting power incorrect"
        );
    }
}
