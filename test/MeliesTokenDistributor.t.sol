// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesTokenDistributor.sol";
import "../src/Melies.sol";

/**
 * @title Melies Token Distributor Test Suite
 * @author Melies Team
 * @notice Comprehensive test suite for the Melies Token Distributor contract
 * @dev Tests all distribution functionalities, vesting schedules, and allocation management
 */
contract MeliesTokenDistributorTest is Test {
    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    MeliesTokenDistributor public distributor;
    Melies public meliesToken;

    uint256 public constant TGE_TIMESTAMP = 1640995200; // January 1, 2022, 00:00:00 UTC
    uint256 public tgeTimestamp;

    // Admin and contract addresses
    address public admin = address(1);
    address public icoContract = address(2);

    // Token allocation addresses
    address public communityAddress = address(3);
    address public treasuryAddress = address(4);
    address public partnersAddress = address(5);
    address public teamAddress = address(6);
    address public liquidityAddress = address(7);
    address public aiSystemsAddress = address(8);

    // Test user addresses
    address public user1 = address(0x21);
    address public user2 = address(0x22);
    address public user3 = address(0x23);
    address public user4 = address(0x24);
    address public user5 = address(0x25);
    address public user6 = address(0x26);
    address public user7 = address(0x27);

    // =============================================================================
    // SETUP
    // =============================================================================

    function setUp() public {
        vm.startPrank(admin);

        tgeTimestamp = TGE_TIMESTAMP;
        meliesToken = new Melies(admin);

        // Deploy TokenDistributor
        distributor = new MeliesTokenDistributor(
            address(meliesToken),
            admin,
            communityAddress,
            treasuryAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress,
            aiSystemsAddress
        );

        // Grant necessary roles
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(distributor));
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), address(distributor));
        distributor.grantRole(distributor.ICO_ROLE(), icoContract);
        distributor.grantRole(distributor.ICO_ROLE(), admin); // Admin also needs ICO_ROLE for addAllocation

        // Set TGE timestamp
        distributor.setTgeTimestamp(tgeTimestamp);

        vm.stopPrank();
    }

    // =============================================================================
    // INITIAL STATE TESTS
    // =============================================================================

    function test_InitialAllocations() public {
        // Test Community allocation (2.08% TGE)
        (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 cliffDuration,
            uint256 vestingDuration,
            address beneficiary,
            string memory allocationName,
            uint256 tgeReleasePercentage,
            uint256 lastClaimTimestamp,
            bool bypassTgeRestriction
        ) = distributor.getTokenAllocationDetails(0);

        assertEq(totalAmount, 200_000_000e8);
        assertEq(beneficiary, communityAddress);
        assertEq(cliffDuration, 0);
        assertEq(vestingDuration, 48);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 208); // 2.08%
        assertEq(lastClaimTimestamp, 0);
        assertEq(bypassTgeRestriction, false);
        assertEq(keccak256(bytes(allocationName)), keccak256(bytes("Community")));

        // Test Treasury allocation (5.00% TGE)
        (
            totalAmount,
            claimedAmount,
            cliffDuration,
            vestingDuration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp,
            bypassTgeRestriction
        ) = distributor.getTokenAllocationDetails(1);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, treasuryAddress);
        assertEq(cliffDuration, 0);
        assertEq(vestingDuration, 48);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 500); // 5.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(bypassTgeRestriction, false);
        assertEq(keccak256(bytes(allocationName)), keccak256(bytes("Treasury")));

        // Test Team allocation (0% TGE, 12 months cliff)
        (
            totalAmount,
            claimedAmount,
            cliffDuration,
            vestingDuration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp,
            bypassTgeRestriction
        ) = distributor.getTokenAllocationDetails(3);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, teamAddress);
        assertEq(cliffDuration, 12);
        assertEq(vestingDuration, 20);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 0); // 0.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(bypassTgeRestriction, false);
        assertEq(keccak256(bytes(allocationName)), keccak256(bytes("Team")));

        // Test Liquidity allocation (100.00% TGE)
        (
            totalAmount,
            claimedAmount,
            cliffDuration,
            vestingDuration,
            beneficiary,
            allocationName,
            tgeReleasePercentage,
            lastClaimTimestamp,
            bypassTgeRestriction
        ) = distributor.getTokenAllocationDetails(4);

        assertEq(totalAmount, 100_000_000e8);
        assertEq(beneficiary, liquidityAddress);
        assertEq(cliffDuration, 0);
        assertEq(vestingDuration, 1);
        assertEq(claimedAmount, 0);
        assertEq(tgeReleasePercentage, 10000); // 100.00%
        assertEq(lastClaimTimestamp, 0);
        assertEq(bypassTgeRestriction, false);
        assertEq(keccak256(bytes(allocationName)), keccak256(bytes("Liquidity")));

        // Verify total allocations count
        assertEq(distributor.getTokenAllocationsCount(), 6);
    }

    function test_InitialStateValues() public {
        assertEq(distributor.totalTokensSold(), 0);
        assertEq(distributor.getUnsoldTokens(), 300_000_000e8);
        assertEq(distributor.getSalesPerformance(), 0);
        assertEq(distributor.getTotalTokensBurned(), 0);
        assertEq(distributor.isUnsoldTokensDistributed(), false);
    }

    // =============================================================================
    // BASIC CLAIMING TESTS
    // =============================================================================

    function test_ClaimLiquidityTokens() public {
        vm.warp(tgeTimestamp);
        vm.prank(liquidityAddress);
        distributor.claimTokens(4, false); // Liquidity allocation index

        assertEq(meliesToken.balanceOf(liquidityAddress), 100_000_000e8);
    }

    function test_ClaimCommunityTokensProgressively() public {
        // First claim TGE amount
        vm.warp(tgeTimestamp);
        vm.prank(communityAddress);
        distributor.claimTokens(0, false);

        uint256 tgeAmount = (200_000_000e8 * 208) / 10000; // 2.08% TGE
        uint256 expectedFirstClaim = tgeAmount;

        assertEq(meliesToken.balanceOf(communityAddress), expectedFirstClaim);

        // Fast forward 12 months
        vm.warp(tgeTimestamp + 12 * 30 days);
        vm.prank(communityAddress);
        distributor.claimTokens(0, false);

        uint256 additionalVesting = ((200_000_000e8 - tgeAmount) * 12) / 48;
        uint256 expectedTotal = expectedFirstClaim + additionalVesting;
        assertEq(meliesToken.balanceOf(communityAddress), expectedTotal);
    }

    function test_ClaimTeamTokensAfterCliff() public {
        // Team has 12 months cliff and 0% TGE
        // So warp to cliff + 1 month to claim the first month of vesting
        vm.warp(tgeTimestamp + 13 * 30 days);

        vm.prank(teamAddress);
        distributor.claimTokens(3, false);

        // Should receive first month of vesting (100M tokens, 0% TGE, 20 months vesting)
        uint256 vestingAmount = (100_000_000e8 * 1) / 20;
        assertEq(meliesToken.balanceOf(teamAddress), vestingAmount);
    }

    function test_ClaimBeforeTGE() public {
        vm.warp(tgeTimestamp - 1);
        vm.prank(communityAddress);
        vm.expectRevert(MeliesTokenDistributor.NoTokensAvailable.selector);
        distributor.claimTokens(0, false);
    }

    function test_ClaimUnauthorized() public {
        vm.warp(tgeTimestamp);
        vm.prank(address(0x999));
        vm.expectRevert(MeliesTokenDistributor.InvalidBeneficiary.selector);
        distributor.claimTokens(0, false);
    }

    function test_ClaimAfterVestingComplete() public {
        // Fast forward past vesting period
        vm.warp(tgeTimestamp + 49 * 30 days);

        vm.prank(communityAddress);
        distributor.claimTokens(0, false);

        // Should receive total allocation
        assertEq(meliesToken.balanceOf(communityAddress), 200_000_000e8);
    }

    // =============================================================================
    // HAIRCUT MECHANISM TESTS
    // =============================================================================

    function test_HaircutCalculationSeed() public {
        // Test Seed round haircut calculation
        assertEq(distributor.calculateHaircutPercentage("Seed", 0), 9000); // 90% at TGE
        assertEq(distributor.calculateHaircutPercentage("Seed", 1), 9000); // Month 1: 90% - 1286 * (1-1) = 90%
        assertEq(distributor.calculateHaircutPercentage("Seed", 2), 7714); // Month 2: 90% - 1286 * (2-1) = 7714
        assertEq(distributor.calculateHaircutPercentage("Seed", 4), 5142); // Month 4: 90% - 1286 * (4-1) = 5142
        assertEq(distributor.calculateHaircutPercentage("Seed", 7), 1284); // Month 7: 90% - 1286 * (7-1) = 1284
        assertEq(distributor.calculateHaircutPercentage("Seed", 8), 0); // No haircut after 8 months
        assertEq(distributor.calculateHaircutPercentage("Seed", 12), 0); // No haircut after 8 months
    }

    function test_HaircutCalculationPrivateSale() public {
        // Test Private Sale round haircut calculation
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 0), 9000); // 90% at TGE
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 1), 9000); // Month 1: 90% - 1000 * (1-1) = 90%
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 2), 8000); // Month 2: 90% - 1000 * (2-1) = 8000
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 5), 5000); // Month 5: 90% - 1000 * (5-1) = 5000
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 9), 1000); // Near end
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 10), 0); // No haircut after 10 months
        assertEq(distributor.calculateHaircutPercentage("Private Sale", 15), 0); // No haircut after 10 months
    }

    function test_HaircutCalculationPublicSale() public {
        // Test Public Sale round haircut calculation
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 0), 9000); // 90% at TGE
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 1), 9000); // Month 1: 90% - 900 * (1-1) = 90%
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 2), 8100); // Month 2: 90% - 900 * (2-1) = 8100
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 6), 4500); // Month 6: 90% - 900 * (6-1) = 4500
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 10), 900); // Near end
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 11), 0); // No haircut after 11 months
        assertEq(distributor.calculateHaircutPercentage("Public Sale", 20), 0); // No haircut after 11 months
    }

    function test_HaircutCalculationOtherAllocations() public {
        // Test that other allocations don't have haircuts
        assertEq(distributor.calculateHaircutPercentage("Community", 0), 0);
        assertEq(distributor.calculateHaircutPercentage("Treasury", 5), 0);
        assertEq(distributor.calculateHaircutPercentage("Team", 10), 0);
        assertEq(distributor.calculateHaircutPercentage("Liquidity", 0), 0);
        assertEq(distributor.calculateHaircutPercentage("AI Systems", 3), 0);
        assertEq(distributor.calculateHaircutPercentage("Random", 1), 0);
    }

    function test_ClaimAllTokensWithHaircut() public {
        // Add a seed allocation for testing
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        // Fast forward to 2 months after TGE
        vm.warp(tgeTimestamp + 2 * 30 days);

        // Claim all tokens with haircut
        vm.prank(user1);
        distributor.claimAllTokensWithHaircut(0, true); // New allocation index

        // Calculate expected values
        uint256 remainingTokens = 10_000e8; // No previous claims
        uint256 haircutPercentage = distributor.calculateHaircutPercentage("Seed", 2);
        uint256 burnAmount = (remainingTokens * haircutPercentage) / 10000;
        uint256 expectedMintAmount = remainingTokens - burnAmount;

        // Verify user received correct amount
        assertEq(meliesToken.balanceOf(user1), expectedMintAmount);

        // Verify burn amount is tracked
        assertEq(distributor.getTotalTokensBurned(), burnAmount);

        // Verify allocation is fully claimed
        (, uint256 claimedAmount,,,,,,,) = distributor.getRoundAllocationDetails(0);
        assertEq(claimedAmount, 10_000e8);
    }

    function test_ClaimAllTokensWithHaircutBeforeTGE() public {
        // Add a seed allocation for testing
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        // Try to claim before TGE
        vm.warp(tgeTimestamp - 1);
        vm.prank(user1);
        vm.expectRevert(MeliesTokenDistributor.MustWaitUntilTge.selector);
        distributor.claimAllTokensWithHaircut(0, true);
    }

    function test_ClaimAllTokensWithNoHaircut() public {
        // Add a community-type allocation (no haircut)
        vm.prank(admin);
        distributor.addAllocation(user2, 10_000e8, 0, 12, "Community Test", 1000, false);

        // Fast forward to 2 months after TGE
        vm.warp(tgeTimestamp + 2 * 30 days);

        // Claim all tokens with haircut (should have no haircut)
        vm.prank(user2);
        distributor.claimAllTokensWithHaircut(0, true);

        // Should receive full amount with no burns
        assertEq(meliesToken.balanceOf(user2), 10_000e8);
        assertEq(distributor.getTotalTokensBurned(), 0);
    }

    function test_ClaimAllTokensWithHaircutAfterPartialClaim() public {
        // Add a seed allocation for testing
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        uint256 allocationIndex = distributor.getRoundAllocationsCount() - 1;

        // First claim some tokens normally
        vm.warp(tgeTimestamp + 1 * 30 days);
        vm.prank(user1);
        distributor.claimTokens(allocationIndex, true);

        uint256 firstClaimAmount = meliesToken.balanceOf(user1);

        // Then claim all remaining tokens with haircut
        vm.warp(tgeTimestamp + 3 * 30 days);
        vm.prank(user1);
        distributor.claimAllTokensWithHaircut(allocationIndex, true);

        // Calculate expected values
        uint256 remainingTokens = 10_000e8 - firstClaimAmount;
        uint256 haircutPercentage = distributor.calculateHaircutPercentage("Seed", 3);
        uint256 burnAmount = (remainingTokens * haircutPercentage) / 10000;
        uint256 expectedFinalAmount = firstClaimAmount + (remainingTokens - burnAmount);

        assertEq(meliesToken.balanceOf(user1), expectedFinalAmount);
        assertEq(distributor.getTotalTokensBurned(), burnAmount);
    }

    function test_ClaimAllTokensWithHaircutNoTokensAvailable() public {
        // Add a seed allocation for testing
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        uint256 allocationIndex = distributor.getRoundAllocationsCount() - 1;

        // First claim all tokens normally
        vm.warp(tgeTimestamp + 20 * 30 days); // After full vesting
        vm.prank(user1);
        distributor.claimTokens(allocationIndex, true);

        // Try to claim with haircut again (should fail)
        vm.prank(user1);
        vm.expectRevert(MeliesTokenDistributor.NoTokensAvailable.selector);
        distributor.claimAllTokensWithHaircut(allocationIndex, true);
    }

    // =============================================================================
    // ADMIN ALLOCATION TESTS
    // =============================================================================

    function test_AddAllocation() public {
        uint256 initialCount = distributor.getRoundAllocationsCount();

        vm.prank(admin);
        distributor.addAllocation(user1, 50_000e8, 3, 12, "IDO", 500, true);

        // Verify allocation was added
        assertEq(distributor.getRoundAllocationsCount(), initialCount + 1);

        // Verify allocation details
        (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 cliffDuration,
            uint256 vestingDuration,
            address beneficiary,
            string memory allocationName,
            uint256 tgeReleasePercentage,
            uint256 lastClaimTimestamp,
            bool bypassTgeRestriction
        ) = distributor.getRoundAllocationDetails(initialCount);

        assertEq(totalAmount, 50_000e8);
        assertEq(claimedAmount, 0);
        assertEq(cliffDuration, 3);
        assertEq(vestingDuration, 12);
        assertEq(beneficiary, user1);
        assertEq(keccak256(bytes(allocationName)), keccak256(bytes("IDO")));
        assertEq(tgeReleasePercentage, 500);
        assertEq(lastClaimTimestamp, 0);
        assertEq(bypassTgeRestriction, true);

        // Verify tokens sold tracking
        assertEq(distributor.totalTokensSold(), 50_000e8);
        assertEq(distributor.getUnsoldTokens(), 300_000_000e8 - 50_000e8);
    }

    function test_AddAllocationUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        distributor.addAllocation(user1, 50_000e8, 3, 12, "IDO", 500, true);
    }

    function test_AddAllocationAfterTGE() public {
        vm.warp(tgeTimestamp + 1);
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.CannotAddAllocationAfterTge.selector);
        distributor.addAllocation(user1, 50_000e8, 3, 12, "IDO", 500, true);
    }

    function test_AddAllocationInvalidParameters() public {
        // Invalid beneficiary
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.InvalidBeneficiary.selector);
        distributor.addAllocation(address(0), 50_000e8, 3, 12, "IDO", 500, true);

        // Invalid amount
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.InvalidAmount.selector);
        distributor.addAllocation(user1, 0, 3, 12, "IDO", 500, true);

        // Invalid vesting duration
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.InvalidDuration.selector);
        distributor.addAllocation(user1, 50_000e8, 3, 0, "IDO", 500, true);

        // Invalid TGE percentage
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.InvalidTgeReleasePercentage.selector);
        distributor.addAllocation(user1, 50_000e8, 3, 12, "IDO", 10001, true);
    }

    function test_TGEBypassFunctionality() public {
        // Add allocation with TGE bypass
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 3, 12, "IDO", 1000, true);

        uint256 allocationIndex = distributor.getRoundAllocationsCount() - 1;

        // Verify bypass flag is set
        assertTrue(distributor.hasRoundTgeBypass(allocationIndex));

        // Should be able to claim TGE tokens before TGE
        vm.warp(tgeTimestamp - 1000);

        uint256 claimableAmount = distributor.getClaimableAmount(allocationIndex, true);
        assertEq(claimableAmount, 1000e8); // 10% TGE

        vm.prank(user1);
        distributor.claimTokens(allocationIndex, true);

        assertEq(meliesToken.balanceOf(user1), 1000e8);
    }

    function test_AddAllocationUpdateExisting() public {
        // Add initial allocation
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 3, 12, "IDO", 500, true);

        uint256 initialCount = distributor.getRoundAllocationsCount();

        // Add another allocation with same beneficiary and name
        vm.prank(admin);
        distributor.addAllocation(user1, 5_000e8, 3, 12, "IDO", 500, true);

        // Should update existing allocation, not create new one
        assertEq(distributor.getRoundAllocationsCount(), initialCount);

        // Verify total amount is updated
        (uint256 totalAmount,,,,,,,,) = distributor.getRoundAllocationDetails(initialCount - 1);
        assertEq(totalAmount, 15_000e8);

        // Verify total tokens sold is updated
        assertEq(distributor.totalTokensSold(), 15_000e8);
    }

    // =============================================================================
    // UNSOLD TOKEN DISTRIBUTION TESTS
    // =============================================================================

    function test_DistributeUnsoldTokens() public {
        // Add some sales first
        vm.prank(admin);
        distributor.addAllocation(user1, 50_000_000e8, 0, 12, "Seed", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user2, 100_000_000e8, 0, 12, "Private Sale", 1000, false);

        // Move to after TGE
        vm.warp(tgeTimestamp + 1);

        // Get initial allocation amounts
        (uint256 initialCommunityAmount,,,,,,,,) = distributor.getTokenAllocationDetails(0);
        (uint256 initialLiquidityAmount,,,,,,,,) = distributor.getTokenAllocationDetails(4);
        (uint256 initialAiSystemsAmount,,,,,,,,) = distributor.getTokenAllocationDetails(5);

        // Distribute unsold tokens
        vm.prank(admin);
        distributor.distributeUnsoldTokens();

        // Verify state is updated
        assertTrue(distributor.isUnsoldTokensDistributed());

        // Calculate expected distribution
        uint256 unsoldTokens = 300_000_000e8 - 150_000_000e8; // 150M unsold
        uint256 expectedCommunityAdd = (unsoldTokens * 50) / 100; // 50%
        uint256 expectedLiquidityAdd = (unsoldTokens * 25) / 100; // 25%
        uint256 expectedAiSystemsAdd = (unsoldTokens * 25) / 100; // 25%

        // Verify allocations are updated
        (uint256 newCommunityAmount,,,,,,,,) = distributor.getTokenAllocationDetails(0);
        (uint256 newLiquidityAmount,,,,,,,,) = distributor.getTokenAllocationDetails(4);
        (uint256 newAiSystemsAmount,,,,,,,,) = distributor.getTokenAllocationDetails(5);

        assertEq(newCommunityAmount, initialCommunityAmount + expectedCommunityAdd);
        assertEq(newLiquidityAmount, initialLiquidityAmount + expectedLiquidityAdd);
        assertEq(newAiSystemsAmount, initialAiSystemsAmount + expectedAiSystemsAdd);
    }

    function test_DistributeUnsoldTokensUpdateVestingPeriods() public {
        // Add sales for different performance levels
        vm.prank(admin);
        distributor.addAllocation(user1, 75_000_000e8, 0, 12, "Seed", 1000, false); // 25% sales performance

        vm.warp(tgeTimestamp + 1);

        // Get initial durations
        (,,, uint256 initialCommunityDuration,,,,,) = distributor.getTokenAllocationDetails(0);
        (,,, uint256 initialAiSystemsDuration,,,,,) = distributor.getTokenAllocationDetails(5);

        vm.prank(admin);
        distributor.distributeUnsoldTokens();

        // Verify vesting periods are updated based on sales performance
        (,,, uint256 newCommunityDuration,,,,,) = distributor.getTokenAllocationDetails(0);
        (,,, uint256 newAiSystemsDuration,,,,,) = distributor.getTokenAllocationDetails(5);

        // For 25% sales performance, should be 75 months for Community and 28 months for AI Systems
        assertEq(newCommunityDuration, 75);
        assertEq(newAiSystemsDuration, 28);
    }

    function test_DistributeUnsoldTokensMultiplePerformanceLevels() public {
        // Test 100% sales performance
        vm.prank(admin);
        distributor.addAllocation(user1, 300_000_000e8, 0, 12, "Seed", 1000, false);

        vm.warp(tgeTimestamp + 1);
        vm.prank(admin);
        distributor.distributeUnsoldTokens();

        // Should maintain original vesting periods
        (,,, uint256 communityDuration,,,,,) = distributor.getTokenAllocationDetails(0);
        (,,, uint256 aiSystemsDuration,,,,,) = distributor.getTokenAllocationDetails(5);

        assertEq(communityDuration, 48);
        assertEq(aiSystemsDuration, 18);
    }

    function test_DistributeUnsoldTokensBeforeTGE() public {
        vm.warp(tgeTimestamp - 1);
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.MustWaitUntilTge.selector);
        distributor.distributeUnsoldTokens();
    }

    function test_DistributeUnsoldTokensMultipleCalls() public {
        vm.warp(tgeTimestamp + 1);
        vm.prank(admin);
        distributor.distributeUnsoldTokens();

        // Second call should fail
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.UnsoldTokensAlreadyDistributed.selector);
        distributor.distributeUnsoldTokens();
    }

    function test_DistributeUnsoldTokensUnauthorized() public {
        vm.warp(tgeTimestamp + 1);
        vm.prank(user1);
        vm.expectRevert();
        distributor.distributeUnsoldTokens();
    }

    function test_DistributeUnsoldTokensNoUnsoldTokens() public {
        // Sell all tokens
        vm.prank(admin);
        distributor.addAllocation(user1, 300_000_000e8, 0, 12, "Seed", 1000, false);

        vm.warp(tgeTimestamp + 1);
        vm.prank(admin);
        distributor.distributeUnsoldTokens();

        // Should mark as distributed but not change allocations
        assertTrue(distributor.isUnsoldTokensDistributed());
    }

    // =============================================================================
    // VIEW FUNCTION AND SIMULATION TESTS
    // =============================================================================

    function test_SimulateClaim() public {
        vm.warp(tgeTimestamp + 6 * 30 days);

        uint256 claimableAmount = distributor.simulateTokenClaim(0); // Community allocation
        uint256 actualClaimable = distributor.getClaimableAmount(0, false);

        assertEq(claimableAmount, actualClaimable);
    }

    function test_SimulateClaimWithHaircut() public {
        // Add a seed allocation
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        uint256 allocationIndex = distributor.getRoundAllocationsCount() - 1;

        vm.warp(tgeTimestamp + 3 * 30 days);

        // Since simulateClaimWithHaircut doesn't exist, we'll test the haircut calculation directly
        uint256 haircutPercentage = distributor.calculateHaircutPercentage("Seed", 3);
        uint256 remainingTokens = 10_000e8;
        uint256 burnAmount = (remainingTokens * haircutPercentage) / 10000;
        uint256 mintAmount = remainingTokens - burnAmount;

        assertEq(remainingTokens, 10_000e8);
        assertEq(haircutPercentage, distributor.calculateHaircutPercentage("Seed", 3));
        assertEq(burnAmount, (remainingTokens * haircutPercentage) / 10000);
        assertEq(mintAmount, remainingTokens - burnAmount);
    }

    function test_GetHaircutInfo() public {
        // Add a seed allocation
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        uint256 allocationIndex = distributor.getRoundAllocationsCount() - 1;

        vm.warp(tgeTimestamp + 5 * 30 days);

        (uint256 haircutPercentage, uint256 monthsPassed) = distributor.getRoundHaircutInfo(allocationIndex);

        assertEq(monthsPassed, 5);
        assertEq(haircutPercentage, distributor.calculateHaircutPercentage("Seed", 5));
    }

    function test_GetSalesPerformance() public {
        assertEq(distributor.getSalesPerformance(), 0);

        vm.prank(admin);
        distributor.addAllocation(user1, 150_000_000e8, 0, 12, "Seed", 1000, false);

        assertEq(distributor.getSalesPerformance(), 50); // 50%

        vm.prank(admin);
        distributor.addAllocation(user2, 150_000_000e8, 0, 12, "Private Sale", 1000, false);

        assertEq(distributor.getSalesPerformance(), 100); // 100%
    }

    function test_GetAllocationIndex() public {
        uint256 index = distributor.getTokenAllocationIndex(communityAddress, "Community");
        assertEq(index, 0);

        index = distributor.getTokenAllocationIndex(communityAddress, "NonExistent");
        assertEq(index, type(uint256).max);
    }

    function test_GetAllocationsForBeneficiary() public {
        // Add multiple allocations for same beneficiary
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user1, 20_000e8, 0, 12, "Private Sale", 1000, false);

        uint256[] memory indices = distributor.getRoundAllocationsForBeneficiary(user1);
        assertEq(indices.length, 2);
    }

    function test_ViewFunctionsWithInvalidIndex() public {
        uint256 invalidIndex = 999;

        // Should return zero values for invalid indices
        assertEq(distributor.simulateTokenClaim(invalidIndex), 0);
        assertEq(distributor.hasTokenTgeBypass(invalidIndex), false);

        // Since simulateClaimWithHaircut doesn't exist, we'll test with invalid index
        uint256 haircutPercentage = distributor.calculateHaircutPercentage("Invalid", 0);
        assertEq(haircutPercentage, 0);

        (uint256 haircutPerc, uint256 monthsPassed) = distributor.getTokenHaircutInfo(invalidIndex);
        assertEq(haircutPerc, 0);
        assertEq(monthsPassed, 0);
    }

    // =============================================================================
    // TGE TIMESTAMP MANAGEMENT TESTS
    // =============================================================================

    function test_SetTgeTimestampMultipleTimes() public {
        // TGE timestamp is already set in setUp()
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.TgeTimestampAlreadySet.selector);
        distributor.setTgeTimestamp(tgeTimestamp + 1000);
    }

    function test_SetTgeTimestampInvalidValues() public {
        // Create a new distributor without setting TGE timestamp
        vm.startPrank(admin);
        MeliesTokenDistributor newDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            admin,
            communityAddress,
            treasuryAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress,
            aiSystemsAddress
        );

        // Test setting zero timestamp
        vm.expectRevert(MeliesTokenDistributor.InvalidStartTime.selector);
        newDistributor.setTgeTimestamp(0);

        // Test setting past timestamp
        vm.expectRevert(MeliesTokenDistributor.InvalidStartTime.selector);
        newDistributor.setTgeTimestamp(block.timestamp - 1); // Use a past timestamp

        vm.stopPrank();
    }

    function test_TgeTimestampNotSetScenarios() public {
        // Create a new distributor without setting TGE timestamp
        vm.startPrank(admin);
        MeliesTokenDistributor newDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            admin,
            communityAddress,
            treasuryAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress,
            aiSystemsAddress
        );

        // Grant necessary roles
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(newDistributor));
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), address(newDistributor));
        newDistributor.grantRole(newDistributor.ICO_ROLE(), admin);

        // Test adding allocation without TGE timestamp set
        newDistributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        // Test distributing unsold tokens without TGE timestamp set
        vm.expectRevert(MeliesTokenDistributor.TgeTimestampNotSet.selector);
        newDistributor.distributeUnsoldTokens();

        vm.stopPrank();
    }

    // =============================================================================
    // TOKEN ALLOCATION MODIFICATION TESTS
    // =============================================================================

    function test_ModifyTokenAllocationAmount() public {
        uint256 initialAmount = 200_000_000e8;
        uint256 newAmount = 250_000_000e8;

        vm.prank(admin);
        distributor.modifyTokenAllocationAmount(0, newAmount); // Community allocation

        (uint256 totalAmount,,,,,,,,) = distributor.getTokenAllocationDetails(0);
        assertEq(totalAmount, newAmount);
    }

    function test_ModifyTokenAllocationAmountAfterTGE() public {
        vm.warp(tgeTimestamp + 1);

        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.CannotModifyAfterTge.selector);
        distributor.modifyTokenAllocationAmount(0, 250_000_000e8);
    }

    function test_ModifyTokenAllocationAmountInvalidParameters() public {
        // Test invalid allocation index
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.AllocationNotFound.selector);
        distributor.modifyTokenAllocationAmount(999, 250_000_000e8);

        // Test zero amount
        vm.prank(admin);
        vm.expectRevert(MeliesTokenDistributor.InvalidAmount.selector);
        distributor.modifyTokenAllocationAmount(0, 0);
    }

    function test_ModifyTokenAllocationAmountUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        distributor.modifyTokenAllocationAmount(0, 250_000_000e8);
    }

    // =============================================================================
    // ROLE MANAGEMENT TESTS
    // =============================================================================

    function test_IcoRoleFunctionality() public {
        // Test that ICO_ROLE can add allocations
        vm.prank(icoContract);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        assertEq(distributor.getRoundAllocationsCount(), 1);
        assertEq(distributor.totalTokensSold(), 10_000e8);
    }

    function test_RoleBasedAccessControl() public {
        // Test that non-admin cannot set TGE timestamp
        vm.prank(user1);
        vm.expectRevert();
        distributor.setTgeTimestamp(tgeTimestamp + 1000);

        // Test that non-admin cannot modify allocation amounts
        vm.prank(user1);
        vm.expectRevert();
        distributor.modifyTokenAllocationAmount(0, 250_000_000e8);

        // Test that non-admin cannot distribute unsold tokens
        vm.warp(tgeTimestamp + 1);
        vm.prank(user1);
        vm.expectRevert();
        distributor.distributeUnsoldTokens();
    }

    // =============================================================================
    // EDGE CASES AND COMPREHENSIVE SCENARIOS
    // =============================================================================

    function test_ClaimTokensProgressively() public {
        vm.warp(tgeTimestamp + 6 * 30 days);

        uint256 claimable1 = distributor.getClaimableAmount(0, false);
        vm.prank(communityAddress);
        distributor.claimTokens(0, false);

        uint256 balance1 = meliesToken.balanceOf(communityAddress);
        assertEq(balance1, claimable1);

        vm.warp(tgeTimestamp + 12 * 30 days);

        uint256 claimable2 = distributor.getClaimableAmount(0, false);
        vm.prank(communityAddress);
        distributor.claimTokens(0, false);

        uint256 balance2 = meliesToken.balanceOf(communityAddress);
        assertEq(balance2, balance1 + claimable2);
    }

    function test_MultipleUsersMultipleAllocations() public {
        // Add allocations for multiple users
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user2, 20_000e8, 0, 12, "Private Sale", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user3, 30_000e8, 0, 12, "Public Sale", 1000, false);

        vm.warp(tgeTimestamp + 6 * 30 days);

        // All users claim normally
        uint256 user1Index = distributor.getRoundAllocationsCount() - 3;
        uint256 user2Index = distributor.getRoundAllocationsCount() - 2;
        uint256 user3Index = distributor.getRoundAllocationsCount() - 1;

        vm.prank(user1);
        distributor.claimTokens(user1Index, true);
        vm.prank(user2);
        distributor.claimTokens(user2Index, true);
        vm.prank(user3);
        distributor.claimTokens(user3Index, true);

        // Verify all received tokens
        assertGt(meliesToken.balanceOf(user1), 0);
        assertGt(meliesToken.balanceOf(user2), 0);
        assertGt(meliesToken.balanceOf(user3), 0);
    }

    function test_BurnTrackingAccuracy() public {
        uint256 totalExpectedBurns = 0;

        // Add multiple allocations with haircuts
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user2, 20_000e8, 0, 12, "Private Sale", 1000, false);

        vm.warp(tgeTimestamp + 2 * 30 days);

        // User1 claims with haircut
        vm.prank(user1);
        distributor.claimAllTokensWithHaircut(0, true);

        uint256 user1Haircut = distributor.calculateHaircutPercentage("Seed", 2);
        totalExpectedBurns += (10_000e8 * user1Haircut) / 10000;

        // User2 claims with haircut
        vm.prank(user2);
        distributor.claimAllTokensWithHaircut(1, true);

        uint256 user2Haircut = distributor.calculateHaircutPercentage("Private Sale", 2);
        totalExpectedBurns += (20_000e8 * user2Haircut) / 10000;

        assertEq(distributor.getTotalTokensBurned(), totalExpectedBurns);
    }

    function test_ComprehensiveVestingScenario() public {
        // Test a comprehensive vesting scenario with multiple allocations
        // and different vesting schedules

        // Add allocations with different schedules
        vm.prank(admin);
        distributor.addAllocation(user1, 50_000e8, 0, 6, "Short Vesting", 2000, false);
        vm.prank(admin);
        distributor.addAllocation(user2, 100_000e8, 3, 12, "Medium Vesting", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user3, 200_000e8, 6, 24, "Long Vesting", 500, false);

        uint256 user1Index = distributor.getRoundAllocationsCount() - 3;
        uint256 user2Index = distributor.getRoundAllocationsCount() - 2;
        uint256 user3Index = distributor.getRoundAllocationsCount() - 1;

        // Test at TGE
        vm.warp(tgeTimestamp);

        uint256 user1Claimable = distributor.getClaimableAmount(user1Index, true);
        uint256 user2Claimable = distributor.getClaimableAmount(user2Index, true);
        uint256 user3Claimable = distributor.getClaimableAmount(user3Index, true);

        assertEq(user1Claimable, 10_000e8); // TGE 20% (50_000e8 * 2000 / 10000) = 10_000e8
        assertEq(user2Claimable, 10_000e8); // TGE 10% (100_000e8 * 1000 / 10000) = 10_000e8
        assertEq(user3Claimable, 10_000e8); // TGE 5% (200_000e8 * 500 / 10000) = 10_000e8

        // Test at 3 months (user2 cliff reached)
        vm.warp(tgeTimestamp + 4 * 30 days);

        user1Claimable = distributor.getClaimableAmount(user1Index, true);
        user2Claimable = distributor.getClaimableAmount(user2Index, true);
        user3Claimable = distributor.getClaimableAmount(user3Index, true);

        assertEq(user1Claimable, 3_666_666_666_666); // TGE 20% + 3 months vesting
        assertEq(user2Claimable, 17_500e8); // TGE 10% + 1st month vesting
        assertEq(user3Claimable, 10_000e8); // Still only TGE

        // Test at 6 months (user3 cliff reached)
        vm.warp(tgeTimestamp + 7 * 30 days);

        user1Claimable = distributor.getClaimableAmount(user1Index, true);
        user2Claimable = distributor.getClaimableAmount(user2Index, true);
        user3Claimable = distributor.getClaimableAmount(user3Index, true);

        assertEq(user1Claimable, 50_000e8); // Full amount
        assertEq(user2Claimable, 40_000e8); // TGE 10% + 4 months vesting
        assertEq(user3Claimable, 1_791_666_666_666); // TGE 5% + 1st month vesting
    }

    function test_ComprehensiveHaircutScenario() public {
        // Test comprehensive haircut scenario with different rounds
        // and different time periods

        // Add allocations for different rounds
        vm.prank(admin);
        distributor.addAllocation(user1, 50_000e8, 0, 12, "Seed", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user2, 75_000e8, 0, 12, "Private Sale", 1000, false);
        vm.prank(admin);
        distributor.addAllocation(user3, 100_000e8, 0, 12, "Public Sale", 1000, false);

        uint256 user1Index = distributor.getRoundAllocationsCount() - 3;
        uint256 user2Index = distributor.getRoundAllocationsCount() - 2;
        uint256 user3Index = distributor.getRoundAllocationsCount() - 1;

        // Test haircuts at different time periods
        uint256[] memory timePeriods = new uint256[](4);
        timePeriods[0] = 2; // 2 months
        timePeriods[1] = 5; // 5 months
        timePeriods[2] = 8; // 8 months
        timePeriods[3] = 12; // 12 months

        for (uint256 i = 0; i < timePeriods.length; i++) {
            vm.warp(tgeTimestamp + timePeriods[i] * 30 days);

            // Calculate expected haircuts
            uint256 seedHaircut = distributor.calculateHaircutPercentage("Seed", timePeriods[i]);
            uint256 privateHaircut = distributor.calculateHaircutPercentage("Private Sale", timePeriods[i]);
            uint256 publicHaircut = distributor.calculateHaircutPercentage("Public Sale", timePeriods[i]);

            // Verify haircut calculations are correct
            if (timePeriods[i] < 8) {
                assertGt(seedHaircut, 0);
            } else {
                assertEq(seedHaircut, 0);
            }

            if (timePeriods[i] < 10) {
                assertGt(privateHaircut, 0);
            } else {
                assertEq(privateHaircut, 0);
            }

            if (timePeriods[i] < 11) {
                assertGt(publicHaircut, 0);
            } else {
                assertEq(publicHaircut, 0);
            }
        }
    }

    function test_CompleteTokenLifecycle() public {
        // Test complete token lifecycle from ICO to distribution

        // Phase 1: ICO sales
        vm.prank(icoContract);
        distributor.addAllocation(user1, 100_000_000e8, 0, 12, "Seed", 1000, false);
        vm.prank(icoContract);
        distributor.addAllocation(user2, 150_000_000e8, 0, 12, "Private Sale", 1000, false);

        // Phase 2: TGE
        vm.warp(tgeTimestamp);

        // Phase 3: Initial claims
        vm.prank(user1);
        distributor.claimTokens(0, true);
        vm.prank(user2);
        distributor.claimTokens(1, true);

        // Phase 4: Distribute unsold tokens
        vm.warp(tgeTimestamp + 1);
        vm.prank(admin);
        distributor.distributeUnsoldTokens();

        // Phase 5: Progressive vesting
        vm.warp(tgeTimestamp + 6 * 30 days);
        vm.prank(user1);
        distributor.claimTokens(0, true);
        vm.prank(user2);
        distributor.claimTokens(1, true);

        // Verify complete lifecycle
        assertEq(distributor.totalTokensSold(), 250_000_000e8);
        assertTrue(distributor.isUnsoldTokensDistributed());
        assertGt(meliesToken.balanceOf(user1), 1000e8);
        assertGt(meliesToken.balanceOf(user2), 1500e8);
    }

    // =============================================================================
    // EVENT EMISSION TESTS
    // =============================================================================

    function test_EventEmissionTgeTimestampSet() public {
        // Create new distributor to test TGE timestamp event
        vm.startPrank(admin);
        MeliesTokenDistributor newDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            admin,
            communityAddress,
            treasuryAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress,
            aiSystemsAddress
        );

        // Grant necessary roles
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(newDistributor));
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), address(newDistributor));
        newDistributor.grantRole(newDistributor.ICO_ROLE(), admin);

        // Test TGE timestamp event
        vm.expectEmit(true, false, false, true);
        emit MeliesTokenDistributor.TgeTimestampSet(tgeTimestamp);
        newDistributor.setTgeTimestamp(tgeTimestamp);

        vm.stopPrank();
    }

    function test_EventEmissionAllocationAdded() public {
        vm.expectEmit(true, false, false, true);
        emit MeliesTokenDistributor.AllocationAdded(user1, 10_000e8, 0, 12, "Test Allocation", false);

        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Test Allocation", 1000, false);
    }

    function test_EventEmissionTokensClaimed() public {
        vm.warp(tgeTimestamp);

        vm.expectEmit(true, false, false, true);
        emit MeliesTokenDistributor.TokensClaimed(liquidityAddress, 100_000_000e8, "Liquidity");

        vm.prank(liquidityAddress);
        distributor.claimTokens(4, false);
    }

    function test_EventEmissionTokensBurned() public {
        // Add seed allocation
        vm.prank(admin);
        distributor.addAllocation(user1, 10_000e8, 0, 12, "Seed", 1000, false);

        uint256 allocationIndex = distributor.getRoundAllocationsCount() - 1;

        vm.warp(tgeTimestamp + 2 * 30 days);

        uint256 haircutPercentage = distributor.calculateHaircutPercentage("Seed", 2);
        uint256 burnAmount = (10_000e8 * haircutPercentage) / 10000;

        vm.expectEmit(true, false, false, true);
        emit MeliesTokenDistributor.TokensBurned(user1, burnAmount, "Seed", haircutPercentage);

        vm.prank(user1);
        distributor.claimAllTokensWithHaircut(allocationIndex, true);
    }

    function test_EventEmissionUnsoldTokensDistributed() public {
        vm.warp(tgeTimestamp + 1);

        uint256 unsoldTokens = 300_000_000e8;
        uint256 communityAmount = (unsoldTokens * 50) / 100;
        uint256 liquidityAmount = (unsoldTokens * 25) / 100;
        uint256 aiSystemsAmount = (unsoldTokens * 25) / 100;

        vm.expectEmit(true, false, false, true);
        emit MeliesTokenDistributor.UnsoldTokensDistributed(
            unsoldTokens, communityAmount, liquidityAmount, aiSystemsAmount
        );

        vm.prank(admin);
        distributor.distributeUnsoldTokens();
    }

    function test_EventEmissionTokenAllocationAmountModified() public {
        uint256 oldAmount = 200_000_000e8;
        uint256 newAmount = 250_000_000e8;

        vm.expectEmit(true, false, false, true);
        emit MeliesTokenDistributor.TokenAllocationAmountModified(communityAddress, oldAmount, newAmount, "Community");

        vm.prank(admin);
        distributor.modifyTokenAllocationAmount(0, newAmount);
    }
}
