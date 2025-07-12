// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesTokenDistributor.sol";
import "../src/Melies.sol";

contract MeliesTokenDistributorTest is Test {
    MeliesTokenDistributor public distributor;
    Melies public meliesToken;
    uint256 public tgeTimestamp;

    address public admin = address(1);
    address public communityAddress = address(2);
    address public treasuryAddress = address(3);
    address public partnersAddress = address(4);
    address public teamAddress = address(5);
    address public liquidityAddress = address(6);
    address public aiSystemsAddress = address(7);

    function setUp() public {
        vm.startPrank(admin);

        tgeTimestamp = 2;
        meliesToken = new Melies(admin);

        distributor = new MeliesTokenDistributor(
            address(meliesToken),
            tgeTimestamp,
            admin,
            communityAddress,
            treasuryAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress,
            aiSystemsAddress
        );

        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(distributor));

        vm.stopPrank();
    }

    function test_InitialAllocations() public {
        // Test Community allocation (2.08% TGE)
        (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 startTime,
            uint256 duration,
            address beneficiary,
            string memory allocationName,
            uint256 tgeReleasePercentage,
            uint256 lastClaimTimestamp
        ) = distributor.allocations(0);

        assertEq(totalAmount, 200_000_000e8);
        assertEq(beneficiary, communityAddress);
        assertEq(startTime, tgeTimestamp);
        assertEq(duration, 48 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 208); // 2.08%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Community"))
        );

        // Test Treasury allocation (5.00% TGE)
        (
            totalAmount,
            claimedAmount,
            startTime,
            duration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp
        ) = distributor.allocations(1);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, treasuryAddress);
        assertEq(startTime, tgeTimestamp);
        assertEq(duration, 48 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 500); // 5.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Treasury"))
        );

        // Test Partners allocation (10.00% TGE)
        (
            totalAmount,
            claimedAmount,
            startTime,
            duration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp
        ) = distributor.allocations(2);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, partnersAddress);
        assertEq(startTime, tgeTimestamp);
        assertEq(duration, 18 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 1000); // 10.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Partners"))
        );

        // Test Team allocation (0% TGE)
        (
            totalAmount,
            claimedAmount,
            startTime,
            duration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp
        ) = distributor.allocations(3);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, teamAddress);
        assertEq(startTime, tgeTimestamp + 12 * 30 days);
        assertEq(duration, 20 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 0); // 0.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(keccak256(bytes(allocationName)), keccak256(bytes("Team")));

        // Test Liquidity allocation (100.00% TGE)
        (
            totalAmount,
            claimedAmount,
            startTime,
            duration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp
        ) = distributor.allocations(4);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, liquidityAddress);
        assertEq(startTime, tgeTimestamp);
        assertEq(duration, 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 10000); // 100.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Liquidity"))
        );

        // Test AI Systems allocation (10.00% TGE)
        (
            totalAmount,
            claimedAmount,
            startTime,
            duration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp
        ) = distributor.allocations(5);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, aiSystemsAddress);
        assertEq(startTime, tgeTimestamp);
        assertEq(duration, 18 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 1000); // 10.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("AI Systems"))
        );
    }

    function test_ClaimLiquidityTokens() public {
        vm.warp(2);
        vm.prank(liquidityAddress);
        distributor.claimTokens(4); // Liquidity allocation index

        assertEq(meliesToken.balanceOf(liquidityAddress), 100_000_000e8);
    }

    function test_ClaimCommunityTokens() public {
        // First claim TGE amount
        vm.warp(tgeTimestamp);
        vm.prank(communityAddress);
        distributor.claimTokens(0);
        uint256 communityBalance = meliesToken.balanceOf(communityAddress);
        assertEq(
            communityBalance,
            4_160_000e8 + (((200_000_000e8 - 4_160_000e8) * 1) / 48)
        ); // 2.08% of 200M = 4_160_000 + 1/48 of the remaining tokens

        // Fast forward 12 months
        vm.warp(tgeTimestamp + 12 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0);

        uint256 vestingAmount = communityBalance +
            (((200_000_000e8 - 4_160_000e8) * 12) / 48);
        // Should receive TGE (2.08%) + 25% of remaining tokens (100 - 2.08 = 97.92)
        assertEq(meliesToken.balanceOf(communityAddress), vestingAmount);
    }

    function test_ClaimTreasuryTokensAtTGE() public {
        // Can claim TGE amount immediately (Treasury has no cliff)
        vm.warp(tgeTimestamp);
        vm.prank(treasuryAddress);
        distributor.claimTokens(1);

        // First claim includes TGE + first month of vesting
        uint256 tgeAmount = 5_000_000e8;
        uint256 firstMonthVesting = ((100_000_000e8 - tgeAmount) * 1) / 48;
        uint256 expectedFirstClaim = tgeAmount + firstMonthVesting;
        assertEq(meliesToken.balanceOf(treasuryAddress), expectedFirstClaim);

        // Can also claim more after some time (no cliff)
        vm.warp(tgeTimestamp + 6 * 30 days);
        vm.prank(treasuryAddress);
        distributor.claimTokens(1);

        uint256 additionalVesting = ((100_000_000e8 - tgeAmount) * 6) / 48;
        uint256 expectedTotalAfter6Months = expectedFirstClaim +
            additionalVesting;
        assertEq(
            meliesToken.balanceOf(treasuryAddress),
            expectedTotalAfter6Months
        );
    }

    function test_ClaimTeamTokensAfterCliff() public {
        // Team has 12 months cliff and 0% TGE
        vm.warp(tgeTimestamp + 12 * 30 days);

        vm.prank(teamAddress);
        distributor.claimTokens(3);

        // Should receive first month of vesting (100M tokens, 0% TGE, 20 months vesting)
        uint256 vestingAmount = (100_000_000e8 * 1) / 20;
        assertEq(meliesToken.balanceOf(teamAddress), vestingAmount);
    }

    function test_MultipleClaimsSameAllocation() public {
        // First claim at 6 months
        vm.warp(tgeTimestamp + 6 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0);
        uint256 firstClaim = meliesToken.balanceOf(communityAddress);

        // Calculate expected amount: TGE (2.08%) + 6 months vesting
        uint256 tgeAmount = (200_000_000e8 * 208) / 10000; // 2.08% of total
        uint256 vestingAmount = ((200_000_000e8 - tgeAmount) * 7) / 48; // 7/48 of remaining
        assertEq(firstClaim, tgeAmount + vestingAmount);

        // Second claim at 12 months
        vm.warp(tgeTimestamp + 12 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0);
        uint256 secondClaim = meliesToken.balanceOf(communityAddress) -
            firstClaim;

        // Second claim should be exactly 6 months worth of vesting
        assertEq(secondClaim, ((200_000_000e8 - tgeAmount) * 6) / 48);
    }

    function test_ClaimAfterVestingComplete() public {
        // Fast forward 49 months (past 48-month vesting)
        vm.warp(tgeTimestamp + 49 * 30 days);

        vm.prank(communityAddress);
        distributor.claimTokens(0);

        // Should receive total allocation
        assertEq(meliesToken.balanceOf(communityAddress), 200_000_000e8);
    }

    function test_ClaimZeroTokens() public {
        vm.warp(tgeTimestamp - 1);
        vm.prank(communityAddress);
        vm.expectRevert(MeliesTokenDistributor.NoTokensAvailable.selector);
        distributor.claimTokens(0);
    }

    function test_UnauthorizedClaim() public {
        vm.warp(tgeTimestamp);
        vm.prank(address(8));
        vm.expectRevert(MeliesTokenDistributor.InvalidBeneficiary.selector);
        distributor.claimTokens(0);
    }

    function test_GetClaimableAmount() public {
        // Just after TGE
        vm.warp(tgeTimestamp);

        // Community should have 2.08% TGE available
        uint256 communityClaimable = distributor.getClaimableAmount(0);
        assertEq(
            communityClaimable,
            (200_000_000e8 * 208) /
                10000 +
                (((200_000_000e8 - (200_000_000e8 * 208) / 10000) * 1) / 48)
        ); // 2.08% of 200M + 1/48 of remaining

        // Fast forward 24 months
        vm.warp(tgeTimestamp + 24 * 30 days);

        // Community should have TGE + remaining tokens vested (25/48 of remaining after TGE)
        communityClaimable = distributor.getClaimableAmount(0);
        uint256 tgeAmount = (200_000_000e8 * 208) / 10000;
        uint256 expectedVesting = ((200_000_000e8 - tgeAmount) * 25) / 48;
        assertEq(communityClaimable, tgeAmount + expectedVesting);

        // Team should have 0% TGE + just started vesting (after 12-month cliff)
        uint256 teamClaimable = distributor.getClaimableAmount(3);
        uint256 teamTGE = 0; // 0% TGE
        uint256 teamVesting = (100_000_000e8 * 13) / 20; // 12 months cliff + 12 months vesting
        assertEq(teamClaimable, teamTGE + teamVesting);

        // Liquidity should have full amount available (100% TGE)
        uint256 liquidityClaimable = distributor.getClaimableAmount(4);
        assertEq(liquidityClaimable, 100_000_000e8);
    }
}
