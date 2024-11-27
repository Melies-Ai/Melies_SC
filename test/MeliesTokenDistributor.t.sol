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
    address public foundationAddress = address(3);
    address public partnersAddress = address(4);
    address public teamAddress = address(5);
    address public liquidityAddress = address(6);

    function setUp() public {
        vm.startPrank(admin);

        tgeTimestamp = 2;
        meliesToken = new Melies(admin);

        distributor = new MeliesTokenDistributor(
            address(meliesToken),
            tgeTimestamp,
            admin,
            communityAddress,
            foundationAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress
        );

        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(distributor));

        vm.stopPrank();
    }

    function test_InitialAllocations() public {
        // Test Community allocation (2.04% TGE)
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

        assertEq(totalAmount, 45_000_000e8);
        assertEq(beneficiary, communityAddress);
        assertEq(startTime, tgeTimestamp);
        assertEq(duration, 48 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 204); // 2.04%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Community"))
        );

        // Test Foundation allocation (5.00% TGE)
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

        assertEq(totalAmount, 30_000_000e8);
        assertEq(beneficiary, foundationAddress);
        assertEq(startTime, tgeTimestamp + 6 * 30 days);
        assertEq(duration, 42 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 500); // 5.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Foundation"))
        );

        // Test Partners allocation (5.00% TGE)
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

        assertEq(totalAmount, 25_000_000e8);
        assertEq(beneficiary, partnersAddress);
        assertEq(startTime, tgeTimestamp + 6 * 30 days);
        assertEq(duration, 24 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 500); // 5.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(
            keccak256(bytes(allocationName)),
            keccak256(bytes("Partners"))
        );

        // Test Team allocation (1% TGE)
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

        assertEq(totalAmount, 20_000_000e8);
        assertEq(beneficiary, teamAddress);
        assertEq(startTime, tgeTimestamp + 24 * 30 days);
        assertEq(duration, 24 * 30 days);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 100); // 1.00%
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

        assertEq(totalAmount, 20_000_000e8);
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
    }

    function test_ClaimLiquidityTokens() public {
        vm.warp(2);
        vm.prank(liquidityAddress);
        distributor.claimTokens(4); // Liquidity allocation index

        assertEq(meliesToken.balanceOf(liquidityAddress), 20_000_000e8);
    }

    function test_ClaimCommunityTokens() public {
        // First claim TGE amount
        vm.warp(tgeTimestamp);
        vm.prank(communityAddress);
        distributor.claimTokens(0);
        uint256 communityBalance = meliesToken.balanceOf(communityAddress);
        assertEq(
            communityBalance,
            918_000e8 + (((45_000_000e8 - 918_000e8) * 1) / 48)
        ); // 2.04% of 45M = 918_000 + 1/48 of the remaining tokens

        // Fast forward 12 months
        vm.warp(tgeTimestamp + 12 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0);

        uint256 vestingAmount = communityBalance +
            (((45_000_000e8 - 918_000e8) * 12) / 48);
        // Should receive TGE (2.04%) + 25% of remaining tokens (100 - 2.04 = 97.96)
        assertEq(meliesToken.balanceOf(communityAddress), vestingAmount);
    }

    function test_ClaimFoundationTokensBeforeCliff() public {
        // Can claim TGE amount immediately
        vm.warp(tgeTimestamp);
        vm.prank(foundationAddress);
        distributor.claimTokens(1);
        assertEq(meliesToken.balanceOf(foundationAddress), 1_500_000e8); // 5.00% of 30M

        // But can't claim more until cliff ends
        vm.warp(tgeTimestamp + 6 * 30 days - 1);
        vm.prank(foundationAddress);
        vm.expectRevert(MeliesTokenDistributor.NoTokensAvailable.selector);
        distributor.claimTokens(1);
    }

    function test_ClaimFoundationTokensAfterCliff() public {
        // Fast forward 12 months
        vm.warp(tgeTimestamp + 12 * 30 days);

        vm.prank(foundationAddress);
        distributor.claimTokens(1);

        // Should receive TGE (5%) + 6/42 of remaining tokens
        uint256 vestingAmount = 1_500_000e8 +
            (((30_000_000e8 - 1_500_000e8) * 7) / 42);
        assertEq(meliesToken.balanceOf(foundationAddress), vestingAmount);
    }

    function test_MultipleClaimsSameAllocation() public {
        // First claim at 6 months
        vm.warp(tgeTimestamp + 6 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0);
        uint256 firstClaim = meliesToken.balanceOf(communityAddress);

        // Calculate expected amount: TGE (2.04%) + 6 months vesting
        uint256 tgeAmount = (45_000_000e8 * 204) / 10000; // 2.04% of total
        uint256 vestingAmount = ((45_000_000e8 - tgeAmount) * 7) / 48; // 6/48 of remaining
        assertEq(firstClaim, tgeAmount + vestingAmount);

        // Second claim at 12 months
        vm.warp(tgeTimestamp + 12 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0);
        uint256 secondClaim = meliesToken.balanceOf(communityAddress) -
            firstClaim;

        // Second claim should be exactly 6 months worth of vesting
        assertEq(secondClaim, ((45_000_000e8 - tgeAmount) * 6) / 48);
    }

    function test_ClaimAfterVestingComplete() public {
        // Fast forward 49 months (past 48-month vesting)
        vm.warp(tgeTimestamp + 49 * 30 days);

        vm.prank(communityAddress);
        distributor.claimTokens(0);

        // Should receive total allocation
        assertEq(meliesToken.balanceOf(communityAddress), 45_000_000e8);
    }

    function test_ClaimZeroTokens() public {
        vm.warp(tgeTimestamp - 1);
        vm.prank(communityAddress);
        vm.expectRevert(MeliesTokenDistributor.NoTokensAvailable.selector);
        distributor.claimTokens(0);
    }

    function test_UnauthorizedClaim() public {
        vm.warp(tgeTimestamp);
        vm.prank(address(7));
        vm.expectRevert(MeliesTokenDistributor.InvalidBeneficiary.selector);
        distributor.claimTokens(0);
    }

    function test_GetClaimableAmount() public {
        // Just after TGE
        vm.warp(tgeTimestamp);

        // Community should have 2.04% TGE available
        uint256 communityClaimable = distributor.getClaimableAmount(0);
        assertEq(
            communityClaimable,
            (45_000_000e8 * 204) /
                10000 +
                (((45_000_000e8 - (45_000_000e8 * 204) / 10000) * 1) / 48)
        ); // 2.04% of 45M + 1/48 of remaining

        // Fast forward 24 months
        vm.warp(tgeTimestamp + 24 * 30 days);

        // Community should have TGE + remaining tokens vested (25/48 of remaining after TGE)
        communityClaimable = distributor.getClaimableAmount(0);
        uint256 tgeAmount = (45_000_000e8 * 204) / 10000;
        uint256 expectedVesting = ((45_000_000e8 - tgeAmount) * 25) / 48;
        assertEq(communityClaimable, tgeAmount + expectedVesting);

        // Team should have 1% TGE + just started vesting (after 24-month cliff)
        uint256 teamClaimable = distributor.getClaimableAmount(3);
        uint256 teamTGE = (20_000_000e8 * 100) / 10000; // 1% TGE
        uint256 teamVesting = ((20_000_000e8 - teamTGE) * 1) / 24; // First month after cliff
        assertEq(teamClaimable, teamTGE + teamVesting);

        // Liquidity should have full amount available (100% TGE)
        uint256 liquidityClaimable = distributor.getClaimableAmount(4);
        assertEq(liquidityClaimable, 20_000_000e8);
    }
}
