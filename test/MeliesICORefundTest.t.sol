// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesICO.sol";
import "../src/interfaces/IMeliesICO.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

import {MockMelies, MockMeliesICO} from "../src/mock/MockMelies.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

contract MeliesICORefundTest is Test {
    MockMeliesICO public meliesICO;
    MockMelies public meliesToken;
    uint256 public tgeTimestamp;
    MockERC20 public usdcToken;
    MockERC20 public usdtToken;
    MockUniswapV2Router02 public uniswapRouter;
    MockChainlinkAggregator public ethUsdPriceFeed;

    address public admin;
    address public pauser;
    address public minter;
    address public burner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_ETH_PRICE = 2000; // $2000 per ETH
    uint256 public constant TGE_TIMESTAMP = 1640995200; // January 1, 2022, 00:00:00 UTC

    bytes4 private constant ENFORCED_PAUSE_SELECTOR =
        bytes4(keccak256("EnforcedPause()"));

    function setUp() public {
        admin = address(this);
        pauser = address(0x1);
        minter = address(0x2);
        burner = address(0x3);
        user1 = address(0x4);
        user2 = address(0x5);

        tgeTimestamp = block.timestamp + 21 days;
        meliesToken = new MockMelies(admin, tgeTimestamp);

        vm.startPrank(admin);
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), pauser);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), minter);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), burner);
        vm.stopPrank();
        // Deploy mock contracts
        usdcToken = new MockERC20("USDC", "USDC");
        usdtToken = new MockERC20("USDT", "USDT");
        uniswapRouter = new MockUniswapV2Router02();
        ethUsdPriceFeed = new MockChainlinkAggregator();

        // Deploy MeliesICO
        meliesICO = new MockMeliesICO(
            address(meliesToken),
            address(usdcToken),
            address(usdtToken),
            address(uniswapRouter),
            address(ethUsdPriceFeed),
            TGE_TIMESTAMP
        );

        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addToWhitelist(1, addresses);

        // Set up initial ETH price
        ethUsdPriceFeed.updateAnswer(int256(INITIAL_ETH_PRICE));
        uniswapRouter.setExchangeRate(
            address(0),
            address(usdcToken),
            INITIAL_ETH_PRICE
        );

        // Grant MINTER_ROLE to ICO contract
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
    }

    // 1. Contract Deployment and Initialization

    function testDeployment() public view {
        assertEq(address(meliesICO.meliesToken()), address(meliesToken));
        assertEq(address(meliesICO.usdcToken()), address(usdcToken));
        assertEq(address(meliesICO.usdtToken()), address(usdtToken));
        assertEq(address(meliesICO.uniswapRouter()), address(uniswapRouter));
        assertEq(
            address(meliesICO.ethUsdPriceFeed()),
            address(ethUsdPriceFeed)
        );
        assertEq(meliesICO.tgeTimestamp(), TGE_TIMESTAMP);
    }

    function testInitialRoles() public view {
        assertTrue(meliesICO.hasRole(meliesICO.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(meliesICO.hasRole(meliesICO.ADMIN_ROLE(), admin));
    }

    // Refund Mechanisms

    function test_RefundMechanisms() public {
        // Setup a sale round with a high soft cap
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            500_000e6, // High soft cap
            100e6,
            10_000e6,
            30 days,
            180 days,
            10,
            7 days
        );

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        usdtToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdt(1000e6);

        // End ICO
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // Check initial USDC balance
        uint256 initialUsdcBalance = usdcToken.balanceOf(user1);
        uint256 initialUsdtBalance = usdtToken.balanceOf(user1);

        // Request refund
        vm.prank(user1);
        meliesICO.refund();

        // Check final USDC balance
        uint256 finalUsdcBalance = usdcToken.balanceOf(user1);
        uint256 finalUsdtBalance = usdtToken.balanceOf(user1);
        assertEq(
            finalUsdcBalance - initialUsdcBalance,
            1000e6,
            "User should receive full refund"
        );
        assertEq(
            finalUsdtBalance - initialUsdtBalance,
            1000e6,
            "User should receive full refund"
        );

        // Check that allocation is zeroed out
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(
            allocation.totalTokenAmount,
            0,
            "Token allocation should be zero after refund"
        );
        assertEq(
            allocation.totalUsdcAmount,
            0,
            "USDC allocation should be zero after refund"
        );
        assertEq(
            allocation.totalUsdtAmount,
            0,
            "USDT allocation should be zero after refund"
        );

        // Attempt to claim tokens after refund (should fail)
        vm.expectRevert(IMeliesICO.ClaimingNotEnabled.selector);
        vm.prank(user1);
        meliesICO.claimTokens();
    }

    function test_RefundWhenSoftCapNotReached() public {
        // Setup a sale round with a high soft cap
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            500_000e6, // High soft cap
            100e6,
            10_000e6,
            30 days,
            180 days,
            10,
            7 days
        );

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // End ICO
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // Check initial USDC balance
        uint256 initialBalance = usdcToken.balanceOf(user1);

        // Request refund
        vm.prank(user1);
        meliesICO.refund();

        // Check final USDC balance
        uint256 finalBalance = usdcToken.balanceOf(user1);
        assertEq(
            finalBalance - initialBalance,
            1000e6,
            "User should receive full refund"
        );
    }

    function test_RefundWhenSoftCapReached() public {
        // Setup a sale round with a low soft cap
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6, // Low soft cap
            100e6,
            100_000e6,
            30 days,
            180 days,
            10,
            7 days
        );

        // User buys tokens to reach soft cap
        usdcToken.mint(user1, 100_000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 100_000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(100_000e6);

        // End ICO
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        meliesICO.endIco();

        // Attempt refund (should fail)
        vm.expectRevert(IMeliesICO.RefundNotAvailable.selector);
        vm.prank(user1);
        meliesICO.refund();
    }

    function test_RefundBeforeIcoEnds() public {
        setupSaleRound();

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // Attempt refund before ICO ends (should fail)
        vm.expectRevert(IMeliesICO.IcoNotEndedYet.selector);
        vm.prank(user1);
        meliesICO.refund();
    }

    function test_RefundMultipleUsersAndRounds() public {
        setupMultipleSaleRounds();
        uint256 startTime = 2;
        uint256 middleTime = 2 + 7 days;
        uint256 endTime = 2 + 14 days;
        vm.warp(startTime);

        // Users buy tokens in different rounds
        usdcToken.mint(user1, 2000e6);
        usdtToken.mint(user2, 3000e6);

        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);
        vm.prank(user2);
        usdtToken.approve(address(meliesICO), 3000e6);

        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6); //Round 1
        vm.warp(middleTime);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6); // Round 2
        vm.prank(user2);
        meliesICO.buyWithUsdt(3000e6); // Round 2
        // End ICO
        vm.warp(endTime);
        vm.prank(admin);
        meliesICO.endIco();
        // Users request refunds
        uint256 user1InitialBalance = usdcToken.balanceOf(user1);
        uint256 user2InitialBalance = usdtToken.balanceOf(user2);
        vm.prank(user1);
        meliesICO.refund();
        vm.prank(user2);
        meliesICO.refund();
        assertEq(
            usdcToken.balanceOf(user1) - user1InitialBalance,
            2000e6,
            "User1 should receive full refund"
        );
        assertEq(
            usdtToken.balanceOf(user2) - user2InitialBalance,
            3000e6,
            "User2 should receive full refund"
        );
    }

    function test_RefundMultipleRoundsWithDifferentSoftCapStatus() public {
        uint256 startTime = block.timestamp;
        uint256 endTime1 = startTime + 7 days;
        uint256 endTime2 = endTime1 + 7 days;

        meliesICO.addSaleRound(
            startTime,
            endTime1,
            0.1e6,
            1_000_000e6,
            100_000e6, // Low soft cap (will be reached)
            100e6,
            100_000e6,
            30 days,
            180 days,
            10,
            7 days
        );

        meliesICO.addSaleRound(
            endTime1,
            endTime2,
            0.2e6,
            2_000_000e6,
            500_000e6, // High soft cap (won't be reached)
            200e6,
            150_000e6,
            60 days,
            360 days,
            5,
            14 days
        );

        // Users buy tokens in different rounds
        usdcToken.mint(user1, 150_000e6);
        usdcToken.mint(user2, 150_000e6);

        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 150_000e6);
        vm.prank(user2);
        usdcToken.approve(address(meliesICO), 150_000e6);

        vm.prank(user1);
        meliesICO.buyWithUsdc(100_000e6); // Round 1 (reaches soft cap)
        vm.warp(endTime1);
        vm.prank(user1);
        meliesICO.buyWithUsdc(50_000e6); // Round 2 (doesn't reach soft cap)
        vm.prank(user2);
        meliesICO.buyWithUsdc(150_000e6); // Round 2 (doesn't reach soft cap)

        // End ICO
        vm.warp(endTime2);
        vm.prank(admin);
        meliesICO.endIco();

        // Users request refunds
        uint256 user1InitialBalance = usdcToken.balanceOf(user1);
        uint256 user2InitialBalance = usdcToken.balanceOf(user2);

        vm.prank(user1);
        meliesICO.refund();
        vm.prank(user2);
        meliesICO.refund();

        assertEq(
            usdcToken.balanceOf(user1) - user1InitialBalance,
            50_000e6,
            "User1 should receive partial refund"
        );
        assertEq(
            usdcToken.balanceOf(user2) - user2InitialBalance,
            150_000e6,
            "User2 should receive full refund"
        );
    }

    function test_RefundAfterPartialClaiming() public {
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();
        // User claims some tokens
        vm.prank(user1);
        meliesICO.claimTokens();
        // Attempt refund after partial claiming (should fail)
        vm.expectRevert(IMeliesICO.RefundNotAvailable.selector);
        vm.prank(user1);
        meliesICO.refund();
    }

    function test_RefundWithNoAllocation() public {
        setupSaleRound();
        // End ICO without any purchases
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        meliesICO.endIco();
        // Attempt refund with no allocation
        vm.expectRevert(IMeliesICO.NoAllocationToRefund.selector);
        vm.prank(user1);
        meliesICO.refund();
    }

    // Helper functions

    function setupSaleRound() internal {
        uint256 startTime = 1;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            30 days,
            180 days,
            10,
            7
        );
    }

    function setupMultipleSaleRounds() internal {
        vm.warp(1);
        uint256 startTime = 2;
        uint256 middleTime = 2 + 7 days;
        uint256 endTime = 2 + 14 days;

        vm.startPrank(admin);
        meliesICO.addSaleRound(
            startTime,
            middleTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            30 days,
            180 days,
            10,
            7
        );

        meliesICO.addSaleRound(
            middleTime,
            endTime,
            0.2e6,
            2_000_000e6,
            200_000e6,
            200e6,
            20_000e6,
            90 days,
            240 days,
            0,
            0
        );
        vm.stopPrank();
    }

    function setupSaleRoundAndPurchase() internal {
        uint256 startTime = block.timestamp;
        setupSaleRound();

        usdcToken.mint(user1, 1_000e6);
        usdcToken.mint(user2, 100_000e6);
        // User buys tokens with 1000 USDC on round 1
        vm.warp(startTime + 1);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1_000e6);
        meliesICO.buyWithUsdc(1000e6); // 10_000 tokens
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        vm.stopPrank();
    }

    function setupMultipleSaleRoundAndPurchase() internal {
        uint256 startTimeRound1 = 2;
        uint256 startTimeRound2 = 2 + 7 days;
        setupMultipleSaleRounds();

        usdcToken.mint(user1, 3000e6);
        usdcToken.mint(user2, 300_000e6);

        // User buys tokens with 2000 USDC on round 1
        vm.warp(startTimeRound1 + 1);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);
        meliesICO.buyWithUsdc(2000e6); // 20_000 tokens
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(10_000e6); // 100_000 tokens
        vm.stopPrank();

        // User buys tokens with 1000 USDC on round 2
        vm.warp(startTimeRound2 + 1);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6); // 5_000 tokens
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 200_000e6);
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        meliesICO.buyWithUsdc(20_000e6); // 100_000 tokens
        vm.stopPrank();
    }

    function setupTgeTimestamp(uint newTgeTimestamp) internal {
        meliesICO.setTgeTimestamp(newTgeTimestamp);
        meliesToken.setTgeTimestamp(newTgeTimestamp);
    }
}
