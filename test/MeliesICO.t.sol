// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
// IMPORTS
// =============================================================================

// Forge testing framework
import "forge-std/Test.sol";

// Core contracts
import "../src/MeliesICO.sol";
import "../src/Melies.sol";
import "../src/MeliesTokenDistributor.sol";

// Interfaces
import "../src/interfaces/IMeliesICO.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// Mock contracts
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

// =============================================================================
// TEST CONTRACT
// =============================================================================

/// @title Melies ICO Test Suite
/// @author Melies Team
/// @notice Comprehensive test suite for the Melies ICO contract
/// @dev Tests all ICO functionalities including sale rounds, whitelist management,
///      purchase mechanisms, refund logic, and administrative functions
/// @custom:security-contact security@melies.com
contract MeliesICOTest is Test {
    // =============================================================================
    // CONSTANTS
    // =============================================================================

    uint256 public constant INITIAL_ETH_PRICE = 2000; // $2000 per ETH
    uint256 public constant TGE_TIMESTAMP = 1640995200; // January 1, 2022, 00:00:00 UTC

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    // Core contracts
    MeliesICO public meliesICO;
    MeliesTokenDistributor public tokenDistributor;
    Melies public meliesToken;

    // Mock contracts
    MockERC20 public usdcToken;
    MockUniswapV2Router02 public uniswapRouter;
    MockChainlinkAggregator public ethUsdPriceFeed;

    // Test addresses
    address public admin;
    address public pauser;
    address public minter;
    address public burner;
    address public user1;
    address public user2;
    address public user3;

    // =============================================================================
    // SETUP AND INITIALIZATION
    // =============================================================================

    /// @notice Set up test environment with all necessary contracts and configurations
    /// @dev Deploys all contracts, sets up roles, and configures initial state
    function setUp() public {
        _setupTestAddresses();
        _deployContracts();
        _configureInitialState();
        _setupRoles();
    }

    /// @dev Initialize test addresses
    function _setupTestAddresses() internal {
        admin = address(0x123);
        pauser = address(0x1);
        minter = address(0x2);
        burner = address(0x3);
        user1 = address(0x4);
        user2 = address(0x5);
        user3 = address(0x6);
    }

    /// @dev Deploy all necessary contracts
    function _deployContracts() internal {
        vm.startPrank(admin);

        // Deploy Melies token
        meliesToken = new Melies(admin);

        // Deploy mock contracts
        usdcToken = new MockERC20("USDC", "USDC");
        uniswapRouter = new MockUniswapV2Router02();
        ethUsdPriceFeed = new MockChainlinkAggregator();

        // Deploy TokenDistributor
        tokenDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            admin,
            address(0x111), // Community
            address(0x222), // Treasury
            address(0x333), // Partners
            address(0x444), // Team
            address(0x555), // Liquidity
            address(0x666) // AI Systems
        );

        // Deploy MeliesICO
        meliesICO = new MeliesICO(
            address(meliesToken),
            address(tokenDistributor),
            address(usdcToken),
            address(uniswapRouter),
            address(ethUsdPriceFeed)
        );

        vm.stopPrank();
    }

    /// @dev Configure initial state and prices
    function _configureInitialState() internal {
        vm.startPrank(admin);
        // Set up initial ETH price
        ethUsdPriceFeed.updateAnswer(int256(INITIAL_ETH_PRICE));
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), INITIAL_ETH_PRICE);

        // Set TGE timestamp (required for allocations)
        tokenDistributor.setTgeTimestamp(TGE_TIMESTAMP);
        vm.stopPrank();
    }

    /// @dev Set up all necessary roles and permissions
    function _setupRoles() internal {
        vm.startPrank(admin);

        // Grant admin roles to admin address
        meliesICO.grantRole(meliesICO.DEFAULT_ADMIN_ROLE(), admin);
        meliesICO.grantRole(meliesICO.ADMIN_ROLE(), admin);

        // Grant roles to Melies token
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), pauser);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), minter);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), burner);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(tokenDistributor));

        // Grant roles to TokenDistributor
        tokenDistributor.grantRole(tokenDistributor.ADMIN_ROLE(), address(meliesICO));
        tokenDistributor.grantRole(tokenDistributor.ICO_ROLE(), address(meliesICO));

        vm.stopPrank();
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /// @dev Set up a basic sale round for testing
    function setupSaleRound() internal {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6, // $0.1 per token
            1_000_000e6, // 1M USDC cap
            100_000e6, // 100k USDC soft cap
            100e6, // 100 USDC min
            100_000e6, // 100k USDC max
            1, // 1 month cliff
            6, // 6 months vesting
            10 // 10% at TGE
        );

        // Add users to whitelist
        address[] memory addresses = new address[](3);
        addresses[0] = user1;
        addresses[1] = user2;
        addresses[2] = user3;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
    }

    /// @dev Set up a sale round with high soft cap for refund testing
    function setupSaleRoundWithHighSoftCap() internal {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6, // $0.1 per token
            1_000_000e6, // 1M USDC cap
            900_000e6, // 900k USDC soft cap (high)
            100e6, // 100 USDC min
            100_000e6, // 100k USDC max
            1, // 1 month cliff
            6, // 6 months vesting
            10 // 10% at TGE
        );

        // Add users to whitelist
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
    }

    /// @dev Set up multiple sale rounds for testing round transitions
    function setupMultipleSaleRounds() internal {
        // Add Seed round (round 0)
        uint256 startTime1 = block.timestamp;
        uint256 endTime1 = startTime1 + 7 days;
        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime1,
            endTime1,
            0.1e6, // $0.1 per token
            1_000_000e6, // 1M USDC cap
            100_000e6, // 100k USDC soft cap
            100e6, // 100 USDC min
            10_000e6, // 10k USDC max
            1, // 1 month cliff
            6, // 6 months vesting
            10 // 10% at TGE
        );

        // Add Private Sale round (round 1)
        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 7 days;
        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime2,
            endTime2,
            0.2e6, // $0.2 per token
            2_000_000e6, // 2M USDC cap
            200_000e6, // 200k USDC soft cap
            200e6, // 200 USDC min
            20_000e6, // 20k USDC max
            3, // 3 months cliff
            8, // 8 months vesting
            0 // 0% at TGE
        );
    }

    /// @dev Set up public sale round with wallet contribution limits
    function setupPublicSaleRound() internal {
        // Add Seed round (round 0)
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.01e6, // $0.01 per token
            600_000e6, // 600k USDC cap
            60_000e6, // 60k USDC soft cap
            100e6, // 100 USDC min
            10_000e6, // 10k USDC max
            12, // 12 months cliff
            18, // 18 months vesting
            10 // 10% at TGE
        );

        // Add Private Sale round (round 1)
        startTime = endTime;
        endTime = startTime + 7 days;

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.025e6, // $0.025 per token
            2_500_000e6, // 2.5M USDC cap
            250_000e6, // 250k USDC soft cap
            100e6, // 100 USDC min
            50_000e6, // 50k USDC max
            9, // 9 months cliff
            15, // 15 months vesting
            20 // 20% at TGE
        );

        // Add Public Sale round (round 2)
        startTime = endTime;
        endTime = startTime + 30 days;

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.05e6, // $0.05 per token
            7_000_000e6, // 7M USDC cap
            1_000_000e6, // 1M USDC soft cap
            100e6, // 100 USDC min
            100_000e6, // 100k USDC max
            0, // No cliff
            6, // 6 months vesting
            40 // 40% at TGE
        );

        // Add users to whitelist for public round
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        vm.prank(admin);
        meliesICO.addToWhitelist(2, addresses);

        // Move to public round
        vm.warp(startTime + 1 days);
    }

    // =============================================================================
    // CONTRACT DEPLOYMENT AND INITIALIZATION TESTS
    // =============================================================================

    function test_Deployment() public view {
        assertEq(address(meliesICO.meliesToken()), address(meliesToken));
        assertEq(address(meliesICO.tokenDistributor()), address(tokenDistributor));
        assertEq(address(meliesICO.usdcToken()), address(usdcToken));
        assertEq(address(meliesICO.uniswapRouter()), address(uniswapRouter));
        assertEq(address(meliesICO.ethUsdPriceFeed()), address(ethUsdPriceFeed));
    }

    function test_InitialRoles() public view {
        assertTrue(meliesICO.hasRole(meliesICO.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(meliesICO.hasRole(meliesICO.ADMIN_ROLE(), admin));
    }

    function test_InitialState() public view {
        assertEq(meliesICO.slippageTolerance(), 50); // 0.5%
        assertEq(meliesICO.totalUsdcRaised(), 0);
        assertEq(meliesICO.icoEnded(), false);
        assertEq(meliesICO.claimEnabled(), false);
    }

    // =============================================================================
    // SLIPPAGE TOLERANCE TESTS
    // =============================================================================

    function test_UpdateSlippageTolerance() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(100); // 1%
        assertEq(meliesICO.slippageTolerance(), 100);
    }

    function test_UpdateSlippageToleranceTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.SlippageToleranceTooHigh.selector);
        meliesICO.updateSlippageTolerance(1001); // 10.01%
    }

    function test_UpdateSlippageToleranceNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        meliesICO.updateSlippageTolerance(100);
    }

    function test_SlippageToleranceUpdatedEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.SlippageToleranceUpdated(100);
        meliesICO.updateSlippageTolerance(100);
    }

    function test_SetSlippageToleranceToZero() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(0);
        assertEq(meliesICO.slippageTolerance(), 0);
    }

    function test_SetSlippageToleranceToMaximum() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(1000); // 10%
        assertEq(meliesICO.slippageTolerance(), 1000);
    }

    function test_SetSlippageToleranceJustBelowMaximum() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(999); // 9.99%
        assertEq(meliesICO.slippageTolerance(), 999);
    }

    function test_SetSlippageToleranceJustAboveMaximum() public {
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.SlippageToleranceTooHigh.selector);
        meliesICO.updateSlippageTolerance(1001); // 10.01%
    }

    function test_SetVerySmallSlippageTolerance() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(1); // 0.01%
        assertEq(meliesICO.slippageTolerance(), 1);
    }

    // =============================================================================
    // SALE ROUND MANAGEMENT TESTS
    // =============================================================================

    function test_AddSaleRound() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6, // $0.1 per token
            1_000_000e6, // 1M USDC cap
            100_000e6, // 100k USDC soft cap
            100e6, // 100 USDC min
            10_000e6, // 10k USDC max
            1, // 1 month cliff
            6, // 6 months vesting
            10 // 10% at TGE
        );

        (
            uint256 startTime_,
            uint256 endTime_,
            uint256 tokenPrice_,
            uint256 maxCap_,
            uint256 softCap_,
            uint256 minPurchase_,
            uint256 maxPurchase_,
            uint256 totalUsdcRaised_,
            bool isFinish_,
            uint256 cliffMonthDuration_,
            uint256 vestingMonthDuration_,
            uint256 tgeReleasePercentage_
        ) = meliesICO.saleRounds(0);

        assertEq(startTime_, startTime);
        assertEq(endTime_, endTime);
        assertEq(tokenPrice_, 0.1e6);
        assertEq(maxCap_, 1_000_000e6);
        assertEq(softCap_, 100_000e6);
        assertEq(minPurchase_, 100e6);
        assertEq(maxPurchase_, 10_000e6);
        assertEq(totalUsdcRaised_, 0);
        assertEq(isFinish_, false);
        assertEq(cliffMonthDuration_, 1);
        assertEq(vestingMonthDuration_, 6);
        assertEq(tgeReleasePercentage_, 10);
    }

    function test_AddSaleRoundInvalidTimeRange() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime - 1; // End before start

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidTimeRange.selector);
        meliesICO.addSaleRound(startTime, endTime, 0.1e6, 1_000_000e6, 100_000e6, 100e6, 10_000e6, 1, 6, 10);
    }

    function test_AddSaleRoundInvalidTokenPrice() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidTokenPrice.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0, // Invalid price
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            1,
            6,
            10
        );
    }

    function test_AddSaleRoundInvalidCap() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidCap.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            0, // Invalid max cap
            100_000e6,
            100e6,
            10_000e6,
            1,
            6,
            10
        );
    }

    function test_AddSaleRoundSoftCapGreaterThanMaxCap() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidCap.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            2_000_000e6, // Soft cap > max cap
            100e6,
            10_000e6,
            1,
            6,
            10
        );
    }

    function test_AddSaleRoundInvalidPurchaseLimits() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidPurchaseLimits.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            10_000e6, // Min > max
            1_000e6,
            1,
            6,
            10
        );
    }

    function test_AddSaleRoundInvalidCliffOrVestingDuration() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidCliffOrVestingDuration.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            49, // 49 months cliff
            1, // 1 month vesting
            10
        );
    }

    function test_AddSaleRoundInvalidTgeReleasePercentage() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidTgeReleasePercentage.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            1,
            6,
            101 // > 100%
        );
    }

    function test_AddSaleRoundNonAdmin() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.prank(user1);
        vm.expectRevert();
        meliesICO.addSaleRound(startTime, endTime, 0.1e6, 1_000_000e6, 100_000e6, 100e6, 10_000e6, 1, 6, 10);
    }

    function test_AddMultipleSaleRounds() public {
        // Add first round
        uint256 startTime1 = block.timestamp;
        uint256 endTime1 = startTime1 + 7 days;
        vm.prank(admin);
        meliesICO.addSaleRound(startTime1, endTime1, 0.1e6, 1_000_000e6, 100_000e6, 100e6, 10_000e6, 1, 6, 10);

        // Add second round
        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 7 days;
        vm.prank(admin);
        meliesICO.addSaleRound(startTime2, endTime2, 0.2e6, 2_000_000e6, 200_000e6, 200e6, 20_000e6, 3, 8, 0);
    }

    function test_AddSaleRoundWithZeroDuration() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime; // Same as start time

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidTimeRange.selector);
        meliesICO.addSaleRound(startTime, endTime, 0.1e6, 1_000_000e6, 100_000e6, 100e6, 10_000e6, 1, 6, 10);
    }

    function test_AddSaleRoundWithOverlappingTimes() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;

        vm.startPrank(admin);
        meliesICO.addSaleRound(startTime, endTime, 0.1e6, 1_000_000e6, 100_000e6, 100e6, 10_000e6, 1, 6, 10);

        // Add overlapping round (should be allowed by contract)
        meliesICO.addSaleRound(
            startTime + 3 days, // Overlaps with first round
            endTime + 3 days,
            0.2e6,
            2_000_000e6,
            200_000e6,
            200e6,
            20_000e6,
            2,
            12,
            20
        );
        vm.stopPrank();
    }

    // =============================================================================
    // WHITELIST MANAGEMENT TESTS
    // =============================================================================

    function test_AddToWhitelist() public {
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        assertTrue(meliesICO.whitelist(0, user1));
        assertTrue(meliesICO.whitelist(0, user2));
    }

    function test_AddToWhitelistEvent() public {
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AddedToWhitelist(0, addresses);
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_RemoveFromWhitelist() public {
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        vm.prank(admin);
        meliesICO.removeFromWhitelist(0, addresses);

        assertFalse(meliesICO.whitelist(0, user1));
        assertFalse(meliesICO.whitelist(0, user2));
    }

    function test_RemoveFromWhitelistEvent() public {
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RemovedFromWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);
    }

    function test_WhitelistNonAdmin() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        vm.prank(user1);
        vm.expectRevert();
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_AddToWhitelistWithDuplicateAddresses() public {
        setupSaleRound();

        address[] memory addresses = new address[](3);
        addresses[0] = user1;
        addresses[1] = user1; // Duplicate
        addresses[2] = user2;

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        assertTrue(meliesICO.whitelist(0, user1));
        assertTrue(meliesICO.whitelist(0, user2));
    }

    function test_AddToWhitelistWithZeroAddress() public {
        setupSaleRound();

        address[] memory addresses = new address[](2);
        addresses[0] = address(0); // Zero address
        addresses[1] = user1;

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        assertTrue(meliesICO.whitelist(0, address(0)));
        assertTrue(meliesICO.whitelist(0, user1));
    }

    function test_WhitelistWithEmptyArray() public {
        setupSaleRound();

        address[] memory addresses = new address[](0);

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_WhitelistWithVeryLargeArray() public {
        setupSaleRound();

        address[] memory addresses = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            addresses[i] = address(uint160(i + 1000));
        }

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        // Verify all addresses were added
        for (uint256 i = 0; i < 100; i++) {
            assertTrue(meliesICO.whitelist(0, address(uint160(i + 1000))));
        }
    }

    function test_MultipleRoundsWhitelist() public {
        // Add multiple sale rounds
        uint256 startTime1 = block.timestamp;
        uint256 endTime1 = startTime1 + 7 days;
        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 7 days;

        vm.startPrank(admin);
        meliesICO.addSaleRound(startTime1, endTime1, 0.1e6, 1_000_000e6, 100_000e6, 100e6, 10_000e6, 1, 6, 10);

        meliesICO.addSaleRound(startTime2, endTime2, 0.2e6, 2_000_000e6, 200_000e6, 200e6, 20_000e6, 2, 12, 20);
        vm.stopPrank();

        // Add users to whitelist for both rounds
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
        vm.prank(admin);
        meliesICO.addToWhitelist(1, addresses);

        // Verify users are whitelisted for both rounds
        assertTrue(meliesICO.whitelist(0, user1));
        assertTrue(meliesICO.whitelist(0, user2));
        assertTrue(meliesICO.whitelist(1, user1));
        assertTrue(meliesICO.whitelist(1, user2));
    }

    // =============================================================================
    // USDC PURCHASE TESTS
    // =============================================================================

    function test_BuyWithUsdc() public {
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 1000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();

        // Check user's allocation
        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 1000e6);

        // Check round total
        (,,,,,,, uint256 totalUsdcRaised_,,,,) = meliesICO.saleRounds(0);
        assertEq(totalUsdcRaised_, 1000e6);
        assertEq(meliesICO.totalUsdcRaised(), 1000e6);
    }

    function test_BuyWithUsdcExactMinimum() public {
        setupSaleRound();

        usdcToken.mint(user1, 100e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 100e6);
        meliesICO.buyWithUsdc(0, 100e6);
        vm.stopPrank();

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 100e6);
    }

    function test_BuyWithUsdcExactMaximum() public {
        setupSaleRound();

        usdcToken.mint(user1, 50_000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 50_000e6);
    }

    function test_BuyWithUsdcBelowMinimum() public {
        setupSaleRound();

        usdcToken.mint(user1, 99e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 99e6);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.buyWithUsdc(0, 99e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcAboveMaximum() public {
        setupSaleRound();

        usdcToken.mint(user1, 50_001e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_001e6);
        vm.expectRevert(IMeliesICO.ExceedsWalletContributionLimit.selector);
        meliesICO.buyWithUsdc(0, 50_001e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcNotWhitelisted() public {
        setupSaleRound();

        address nonWhitelistedUser = address(0x999);
        usdcToken.mint(nonWhitelistedUser, 1000e6);

        vm.startPrank(nonWhitelistedUser);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.expectRevert(IMeliesICO.NotWhitelisted.selector);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcInvalidRoundId() public {
        setupSaleRound();

        usdcToken.mint(user1, 1000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.expectRevert(IMeliesICO.InvalidRoundId.selector);
        meliesICO.buyWithUsdc(1, 1000e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcZeroAmount() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert(IMeliesICO.UsdcAmountMustBeGreaterThanZero.selector);
        meliesICO.buyWithUsdc(0, 0);
    }

    function test_BuyWithUsdcAfterIcoEnded() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.endIco();

        usdcToken.mint(user1, 1000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcExceedsWalletContributionLimit() public {
        setupPublicSaleRound();

        usdcToken.mint(user1, 60_000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 60_000e6);

        // First purchase at the limit
        meliesICO.buyWithUsdc(2, 50_000e6);

        // Try to purchase more (should fail due to wallet limit)
        vm.expectRevert(IMeliesICO.ExceedsWalletContributionLimit.selector);
        meliesICO.buyWithUsdc(2, 100e6);

        vm.stopPrank();
    }

    function test_BuyWithUsdcExceedsRoundCap() public {
        setupSaleRound();

        // Fill up most of the cap with multiple users to avoid wallet limits
        for (uint256 i = 0; i < 20; i++) {
            address user = address(uint160(0x1000 + i));
            usdcToken.mint(user, 50_000e6);

            // Add user to whitelist
            address[] memory addresses = new address[](1);
            addresses[0] = user;
            vm.prank(admin);
            meliesICO.addToWhitelist(0, addresses);

            vm.startPrank(user);
            usdcToken.approve(address(meliesICO), 50_000e6);
            meliesICO.buyWithUsdc(0, 50_000e6);
            vm.stopPrank();
        }

        // Try to exceed the cap
        usdcToken.mint(user2, 101e6);
        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 101e6);
        vm.expectRevert(IMeliesICO.RoundCapExceeded.selector);
        meliesICO.buyWithUsdc(0, 101e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcTokensPurchasedEvent() public {
        setupSaleRound();

        usdcToken.mint(user1, 1000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        // Calculate expected token amount: 1000 USDC / 0.1 USDC per token = 10000 tokens
        uint256 expectedTokens = (1000e6 * 10 ** 8) / 0.1e6;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 1000e6, expectedTokens);
        meliesICO.buyWithUsdc(0, 1000e6);

        vm.stopPrank();
    }

    function test_BuyWithUsdcNoActiveRound() public {
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        vm.expectRevert(IMeliesICO.InvalidRoundId.selector);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcInvalidUsdcAmount() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert(IMeliesICO.UsdcAmountMustBeGreaterThanZero.selector);
        meliesICO.buyWithUsdc(0, 0);
    }

    function test_BuyWithUsdcMultipleRounds() public {
        setupMultipleSaleRounds();

        // Add users to whitelist for both rounds
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
        vm.prank(admin);
        meliesICO.addToWhitelist(1, addresses);

        usdcToken.mint(user1, 2000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);

        vm.warp(2 + 1); // Start of first round
        meliesICO.buyWithUsdc(0, 1000e6);

        // Move to the second round
        vm.warp(2 + 7 days + 1);
        meliesICO.buyWithUsdc(1, 1000e6);
        vm.stopPrank();

        // Check user's allocation for both rounds
        uint256 allocation1 = meliesICO.getUserRoundContribution(user1, 0);
        uint256 allocation2 = meliesICO.getUserRoundContribution(user1, 1);

        assertEq(allocation1, 1000e6);
        assertEq(allocation2, 1000e6);
    }

    function test_BuyWithUsdcWithInsufficientAllowance() public {
        setupSaleRound();

        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 500e6); // Approve less than purchase amount
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(meliesICO), 500e6, 1000e6)
        );
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();
    }

    function test_BuyWithUsdcWithZeroAllowance() public {
        setupSaleRound();

        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        // Don't approve any allowance
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(meliesICO), 0, 1000e6)
        );
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();
    }

    // =============================================================================
    // ETH PURCHASE TESTS
    // =============================================================================

    function test_BuyWithEth() public {
        setupSaleRound();

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}(0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 2000e6); // 1 ETH * $2000 = $2000 USDC
    }

    function test_BuyWithEthNoEthSent() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert(IMeliesICO.NoEthSent.selector);
        meliesICO.buyWithEth{value: 0}(0);
    }

    function test_BuyWithEthInvalidRoundId() public {
        setupSaleRound();

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.InvalidRoundId.selector);
        meliesICO.buyWithEth{value: 1 ether}(1);
    }

    function test_BuyWithEthInvalidEthUsdPrice() public {
        setupSaleRound();

        ethUsdPriceFeed.updateAnswer(0); // Invalid price

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.InvalidEthUsdPrice.selector);
        meliesICO.buyWithEth{value: 1 ether}(0);
    }

    function test_BuyWithEthExactMinimumPurchase() public {
        setupSaleRound();

        // Calculate exact minimum ETH needed (100 USDC minimum / 2000 USD per ETH = 0.05 ETH)
        uint256 exactMinimumEth = 0.05 ether;
        vm.deal(user1, exactMinimumEth);
        vm.prank(user1);
        meliesICO.buyWithEth{value: exactMinimumEth}(0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 100e6); // 100 USDC equivalent
    }

    function test_BuyWithEthExactMaximumPurchase() public {
        setupSaleRound();

        // Calculate exact maximum ETH needed (50k USDC maximum / 2000 USD per ETH = 25 ETH)
        uint256 exactMaximumEth = 25 ether;
        vm.deal(user1, exactMaximumEth);
        vm.prank(user1);
        meliesICO.buyWithEth{value: exactMaximumEth}(0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 50_000e6); // 50k USDC equivalent
    }

    function test_BuyWithEthMultiplePurchases() public {
        setupSaleRound();

        vm.deal(user1, 2 ether);
        vm.startPrank(user1);
        meliesICO.buyWithEth{value: 1 ether}(0);
        meliesICO.buyWithEth{value: 1 ether}(0);
        vm.stopPrank();

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 4000e6); // 4000 USDC equivalent (2 ETH * 2000 USD/ETH)
    }

    function test_BuyWithEthBelowMinimum() public {
        setupSaleRound();

        // Calculate ETH amount below minimum (99 USDC / 2000 USD per ETH = 0.0495 ETH)
        uint256 belowMinimumEth = 0.049 ether;
        vm.deal(user1, belowMinimumEth);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.buyWithEth{value: belowMinimumEth}(0);
    }

    function test_BuyWithEthAboveMaximum() public {
        setupSaleRound();

        // Calculate ETH amount above maximum (100,001 USDC / 2000 USD per ETH = 50.0005 ETH)
        uint256 aboveMaximumEth = 50.001 ether;
        vm.deal(user1, aboveMaximumEth);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        meliesICO.buyWithEth{value: aboveMaximumEth}(0);
    }

    function test_BuyWithEthNoActiveRound() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.InvalidRoundId.selector);
        meliesICO.buyWithEth{value: 1 ether}(0);
    }

    function test_BuyWithEthMultipleRounds() public {
        setupMultipleSaleRounds();

        // Add users to whitelist for both rounds
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
        vm.prank(admin);
        meliesICO.addToWhitelist(1, addresses);

        vm.warp(2 + 1); // Start of first round

        // User buys tokens with ETH in the first round
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}(0);

        // Move to the second round
        vm.warp(2 + 7 days + 1);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}(1);

        // Check user's allocation for both rounds
        uint256 allocation1 = meliesICO.getUserRoundContribution(user1, 0);
        uint256 allocation2 = meliesICO.getUserRoundContribution(user1, 1);

        assertEq(allocation1, 2000e6); // 2000 USDC equivalent
        assertEq(allocation2, 2000e6); // 2000 USDC equivalent
    }

    function test_BuyWithEthWithZeroEthPrice() public {
        setupSaleRound();

        // Set ETH price to zero
        ethUsdPriceFeed.updateAnswer(0);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.InvalidEthUsdPrice.selector);
        meliesICO.buyWithEth{value: 1 ether}(0);
    }

    function test_BuyWithEthWithNegativePrice() public {
        setupSaleRound();

        // Set negative ETH price
        ethUsdPriceFeed.updateAnswer(-2000);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.InvalidEthUsdPrice.selector);
        meliesICO.buyWithEth{value: 1 ether}(0);
    }

    function test_BuyWithEthWithinSlippageTolerance() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        uint256 expectedUsdcAmount = 2000e6; // 1 ETH = 2000 USDC
        uint256 minUsdcAmount = (expectedUsdcAmount * 995) / 1000; // 0.5% slippage

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1995); // Slightly lower rate, within tolerance

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}(0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertGe(allocation, minUsdcAmount);
        assertLe(allocation, expectedUsdcAmount);
    }

    function test_BuyWithEthExceedingSlippageTolerance() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1989); // Just below the tolerance limit

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        vm.expectRevert("Insufficient output amount");
        meliesICO.buyWithEth{value: ethAmount}(0);
    }

    // =============================================================================
    // FIAT PURCHASE TESTS
    // =============================================================================

    function test_AddFiatPurchase() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 1000e6, 0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 1000e6);
    }

    function test_AddFiatPurchaseZeroAmount() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.UsdAmountMustBeGreaterThanZero.selector);
        meliesICO.addFiatPurchase(user1, 0, 0);
    }

    function test_AddFiatPurchaseNonAdmin() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert();
        meliesICO.addFiatPurchase(user2, 1000e6, 0);
    }

    function test_FiatPurchaseExactMinimum() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 100e6, 0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 100e6);
    }

    function test_FiatPurchaseExactMaximum() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 50_000e6, 0);

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 50_000e6);
    }

    function test_FiatPurchaseBelowMinimum() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.addFiatPurchase(user1, 99e6, 0);
    }

    function test_FiatPurchaseAboveMaximum() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        meliesICO.addFiatPurchase(user1, 100_001e6, 0);
    }

    function test_FiatPurchaseMultiplePurchases() public {
        setupSaleRound();

        vm.startPrank(admin);
        meliesICO.addFiatPurchase(user1, 25_000e6, 0);
        meliesICO.addFiatPurchase(user1, 25_000e6, 0);
        vm.stopPrank();

        uint256 allocation = meliesICO.getUserRoundContribution(user1, 0);
        assertEq(allocation, 50_000e6);
    }

    function test_FiatPurchaseExceedingRoundCap() public {
        setupSaleRound();

        // Fill up most of the cap with multiple users to avoid wallet limits
        for (uint256 i = 0; i < 20; i++) {
            address user = address(uint160(0x1000 + i));
            address[] memory addresses = new address[](1);
            addresses[0] = user;
            vm.prank(admin);
            meliesICO.addToWhitelist(0, addresses);

            vm.prank(admin);
            meliesICO.addFiatPurchase(user, 50_000e6, 0);
        }

        // Try to exceed the cap
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.RoundCapExceeded.selector);
        meliesICO.addFiatPurchase(user2, 101e6, 0);
    }

    function test_AddFiatPurchaseWithInvalidRoundId() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidRoundId.selector);
        meliesICO.addFiatPurchase(user1, 1000e6, 1);
    }

    function test_AddFiatPurchaseWithExcessiveAmount() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.ExceedsWalletContributionLimit.selector);
        meliesICO.addFiatPurchase(user1, 100_000e6, 0);
    }

    function test_AddFiatPurchaseAfterRoundEnd() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.addFiatPurchase(user1, 1000e6, 0);
    }

    // =============================================================================
    // ICO MANAGEMENT TESTS
    // =============================================================================

    function test_GetCurrentRoundId() public {
        setupSaleRound();

        uint256 currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);
    }

    function test_GetCurrentRoundIdNoActiveRound() public {
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRoundId();
    }

    function test_GetCurrentRound() public {
        setupSaleRound();

        IMeliesICO.SaleRound memory round = meliesICO.getCurrentRound();
        assertEq(round.tokenPrice, 0.1e6);
    }

    function test_EndIco() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.endIco();

        assertTrue(meliesICO.icoEnded());
        (,,,,,,,, bool isFinish_,,,) = meliesICO.saleRounds(0);
        assertTrue(isFinish_);
    }

    function test_EndIcoNonAdmin() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert();
        meliesICO.endIco();
    }

    function test_EndIcoAlreadyEnded() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.endIco();
    }

    function test_EndIcoWithSoftCapReached() public {
        setupSaleRound();

        // Reach soft cap with multiple users to avoid wallet limits
        usdcToken.mint(user1, 50_000e6);
        usdcToken.mint(user2, 50_000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        // Warp to a time after TGE timestamp
        vm.warp(TGE_TIMESTAMP + 1 days);

        vm.prank(admin);
        meliesICO.endIco();

        assertTrue(meliesICO.claimEnabled());
    }

    function test_EndIcoWithoutSoftCapReached() public {
        setupSaleRound();

        // Don't reach soft cap
        usdcToken.mint(user1, 50_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.IcoEnded(false);
        meliesICO.endIco();

        assertFalse(meliesICO.claimEnabled());
    }

    function test_EndIcoEvent() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.IcoEnded(false);
        meliesICO.endIco();
    }

    // =============================================================================
    // REFUND TESTS
    // =============================================================================

    function test_Refund() public {
        setupSaleRoundWithHighSoftCap();

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();

        // End ICO without reaching soft cap
        vm.prank(admin);
        meliesICO.endIco();

        // User requests refund
        uint256 balanceBefore = usdcToken.balanceOf(user1);
        vm.prank(user1);
        meliesICO.refund();
        uint256 balanceAfter = usdcToken.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000e6);
    }

    function test_RefundNotAvailable() public {
        setupSaleRound();

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();

        // End ICO with soft cap reached using multiple users
        usdcToken.mint(user2, 50_000e6);
        usdcToken.mint(user3, 49_000e6);

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        vm.startPrank(user3);
        usdcToken.approve(address(meliesICO), 49_000e6);
        meliesICO.buyWithUsdc(0, 49_000e6);
        vm.stopPrank();

        // Warp to a time after TGE timestamp
        vm.warp(TGE_TIMESTAMP + 1 days);

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(user1);
        vm.expectRevert();
        meliesICO.refund();
    }

    function test_RefundIcoNotEnded() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert(IMeliesICO.IcoNotEndedYet.selector);
        meliesICO.refund();
    }

    function test_RefundNoAllocation() public {
        setupSaleRoundWithHighSoftCap();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(user1);
        vm.expectRevert(IMeliesICO.NoAllocationToRefund.selector);
        meliesICO.refund();
    }

    function test_RefundForRound() public {
        setupSaleRoundWithHighSoftCap();

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();

        // End ICO
        vm.prank(admin);
        meliesICO.endIco();

        // User requests refund for specific round
        uint256 balanceBefore = usdcToken.balanceOf(user1);
        vm.prank(user1);
        meliesICO.refundForRound(0);
        uint256 balanceAfter = usdcToken.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000e6);
    }

    function test_RefundMultipleUsersAndRounds() public {
        setupMultipleSaleRounds();

        // Add users to whitelist for both rounds
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);
        vm.prank(admin);
        meliesICO.addToWhitelist(1, addresses);

        // Users buy tokens in different rounds
        usdcToken.mint(user1, 2000e6);
        usdcToken.mint(user2, 3000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);
        vm.stopPrank();
        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 3000e6);
        vm.stopPrank();

        vm.warp(2 + 1); // Start of first round
        vm.prank(user1);
        meliesICO.buyWithUsdc(0, 1000e6);

        vm.warp(2 + 7 days + 1); // Start of second round
        vm.prank(user1);
        meliesICO.buyWithUsdc(1, 1000e6);
        vm.prank(user2);
        meliesICO.buyWithUsdc(1, 3000e6);

        // End ICO
        vm.warp(2 + 14 days + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // Users request refunds
        uint256 user1InitialBalance = usdcToken.balanceOf(user1);
        uint256 user2InitialBalance = usdcToken.balanceOf(user2);

        vm.prank(user1);
        meliesICO.refund();
        vm.prank(user2);
        meliesICO.refund();

        assertEq(usdcToken.balanceOf(user1) - user1InitialBalance, 2000e6);
        assertEq(usdcToken.balanceOf(user2) - user2InitialBalance, 3000e6);
    }

    // =============================================================================
    // WITHDRAWAL TESTS
    // =============================================================================

    function test_WithdrawUsdc() public {
        setupSaleRound();

        // Add some USDC to contract
        usdcToken.mint(address(meliesICO), 1000e6);

        vm.prank(admin);
        meliesICO.endIco();

        uint256 balanceBefore = usdcToken.balanceOf(admin);
        vm.prank(admin);
        meliesICO.withdrawUsdc();
        uint256 balanceAfter = usdcToken.balanceOf(admin);

        assertEq(balanceAfter - balanceBefore, 1000e6);
    }

    function test_WithdrawUsdcIcoNotEnded() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.IcoNotEndedYet.selector);
        meliesICO.withdrawUsdc();
    }

    function test_WithdrawEth() public {
        setupSaleRound();

        // Send ETH to contract
        vm.deal(address(meliesICO), 1 ether);

        vm.prank(admin);
        meliesICO.endIco();

        uint256 balanceBefore = admin.balance;
        vm.prank(admin);
        meliesICO.withdrawEth();
        uint256 balanceAfter = admin.balance;

        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function test_WithdrawEthNoEth() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.NoEthToWithdraw.selector);
        meliesICO.withdrawEth();
    }

    function test_WithdrawRoundFunds() public {
        setupSaleRound();

        // Add some purchases to reach soft cap using multiple users to avoid wallet limits
        for (uint256 i = 0; i < 2; i++) {
            address user = address(uint160(0x3000 + i));
            address[] memory addresses = new address[](1);
            addresses[0] = user;
            vm.prank(admin);
            meliesICO.addToWhitelist(0, addresses);

            usdcToken.mint(user, 50_000e6);
            vm.startPrank(user);
            usdcToken.approve(address(meliesICO), 50_000e6);
            meliesICO.buyWithUsdc(0, 50_000e6);
            vm.stopPrank();
        }

        // End ICO
        vm.warp(TGE_TIMESTAMP + 1 days);
        vm.prank(admin);
        meliesICO.endIco();

        // Withdraw round funds
        uint256 balanceBefore = usdcToken.balanceOf(admin);
        vm.prank(admin);
        meliesICO.withdrawRoundFunds(0);
        uint256 balanceAfter = usdcToken.balanceOf(admin);

        assertEq(balanceAfter - balanceBefore, 100_000e6);
    }

    function test_WithdrawRoundFundsNonAdmin() public {
        setupSaleRound();

        vm.prank(user1);
        vm.expectRevert();
        meliesICO.withdrawRoundFunds(0);
    }

    function test_WithdrawRoundFundsRoundNotFinished() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.RoundNotFinished.selector);
        meliesICO.withdrawRoundFunds(0);
    }

    function test_WithdrawRoundFundsSoftCapNotReached() public {
        setupSaleRound();

        // Add small purchase that doesn't reach soft cap
        usdcToken.mint(user1, 50_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        // End ICO
        vm.warp(TGE_TIMESTAMP + 1 days);
        vm.prank(admin);
        meliesICO.endIco();

        // Try to withdraw round funds (should fail)
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.SoftCapNotReached.selector);
        meliesICO.withdrawRoundFunds(0);
    }

    // =============================================================================
    // TOKEN RECOVERY TESTS
    // =============================================================================

    function test_RecoverTokens() public {
        MockERC20 otherToken = new MockERC20("Other", "OTHER");
        otherToken.mint(address(meliesICO), 1000e18);

        vm.prank(admin);
        meliesICO.recoverTokens(address(otherToken), 500e18);

        assertEq(otherToken.balanceOf(admin), 500e18);
    }

    function test_RecoverTokensCannotRecoverMelies() public {
        vm.startPrank(admin);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), admin);
        meliesToken.mint(address(meliesICO), 1000e8);

        vm.expectRevert(IMeliesICO.CannotRecoverMeliesTokens.selector);
        meliesICO.recoverTokens(address(meliesToken), 500e8);
        vm.stopPrank();
    }

    function test_RecoverTokensCannotRecoverUsdc() public {
        usdcToken.mint(address(meliesICO), 1000e6);

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.CannotRecoverUsdcTokens.selector);
        meliesICO.recoverTokens(address(usdcToken), 500e6);
    }

    function test_RecoverTokensInsufficientBalance() public {
        MockERC20 otherToken = new MockERC20("Other", "OTHER");
        otherToken.mint(address(meliesICO), 1000e18);

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InsufficientTokenBalance.selector);
        meliesICO.recoverTokens(address(otherToken), 2000e18);
    }

    // =============================================================================
    // VIEW FUNCTION TESTS
    // =============================================================================

    function test_GetTotalTokensSold() public {
        setupSaleRound();

        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();

        uint256 totalSold = meliesICO.getTotalTokensSold();
        assertEq(totalSold, 10_000e8); // 1000 USDC / 0.1 = 10000 tokens
    }

    function test_GetUnsoldTokens() public {
        uint256 unsold = meliesICO.getUnsoldTokens();
        assertEq(unsold, 300_000_000e8); // Total ICO tokens initially
    }

    function test_GetSalesPerformance() public {
        setupSaleRound();

        usdcToken.mint(user1, 50_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        uint256 performance = meliesICO.getSalesPerformance();
        assertEq(performance, 0);
    }

    function test_IsUnsoldTokensDistributed() public {
        bool distributed = meliesICO.isUnsoldTokensDistributed();
        assertFalse(distributed);
    }

    // =============================================================================
    // WALLET CONTRIBUTION LIMIT TESTS
    // =============================================================================

    function test_WalletCanContributeUpToLimit() public {
        setupPublicSaleRound();

        uint256 contribution1 = 30_000e6;
        uint256 contribution2 = 20_000e6;

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, contribution1, 2);
        assertEq(meliesICO.getWalletContribution(user1, 2), contribution1);

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, contribution2, 2);
        assertEq(meliesICO.getWalletContribution(user1, 2), contribution1 + contribution2);
    }

    function test_WalletCannotExceedContributionLimit() public {
        setupPublicSaleRound();

        uint256 maxContribution = 50_000e6;

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, maxContribution, 2);
        assertEq(meliesICO.getWalletContribution(user1, 2), maxContribution);

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.ExceedsWalletContributionLimit.selector);
        meliesICO.addFiatPurchase(user1, 100e6, 2);
    }

    function test_WalletContributionLimitWorksWithUSDCPurchases() public {
        setupPublicSaleRound();

        usdcToken.mint(user1, 60_000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 60_000e6);

        meliesICO.buyWithUsdc(2, 50_000e6);
        assertEq(meliesICO.getWalletContribution(user1, 2), 50_000e6);

        vm.expectRevert(IMeliesICO.ExceedsWalletContributionLimit.selector);
        meliesICO.buyWithUsdc(2, 100e6);

        vm.stopPrank();
    }

    function test_GetWalletContributionReturnsCorrectAmount() public {
        setupPublicSaleRound();

        assertEq(meliesICO.getWalletContribution(user1, 2), 0);

        uint256 contribution = 25_000e6;
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, contribution, 2);

        assertEq(meliesICO.getWalletContribution(user1, 2), contribution);
    }

    // =============================================================================
    // EVENT EMISSION TESTS
    // =============================================================================

    function test_TokensPurchasedEventEmission() public {
        setupSaleRound();

        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        uint256 expectedTokens = (1000e6 * 10 ** 8) / 0.1e6;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 1000e6, expectedTokens);
        meliesICO.buyWithUsdc(0, 1000e6);
        vm.stopPrank();
    }

    function test_AllocationAddedEventEmission() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AllocationAdded(user1, 10_000e8, 1, 6, 0);
        meliesICO.addFiatPurchase(user1, 1000e6, 0);
    }

    function test_RoundFundsWithdrawnEventEmission() public {
        setupSaleRound();

        usdcToken.mint(user1, 50_000e6);
        usdcToken.mint(user2, 50_000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(0, 50_000e6);
        vm.stopPrank();

        vm.warp(TGE_TIMESTAMP + 1 days);
        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RoundFundsWithdrawn(0, 100_000e6);
        meliesICO.withdrawRoundFunds(0);
    }
}
