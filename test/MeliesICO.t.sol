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

contract MeliesICOTest is Test {
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
        meliesToken = new MockMelies(
            admin,
            pauser,
            minter,
            burner,
            tgeTimestamp
        );
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

    function test_AddedToWhitelistEventSingleAddress() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AddedToWhitelist(0, addresses);
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_AddedToWhitelistEventMultipleAddresses() public {
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AddedToWhitelist(0, addresses);
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_AddedToWhitelistEventDifferentRounds() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AddedToWhitelist(0, addresses);
        meliesICO.addToWhitelist(0, addresses);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AddedToWhitelist(1, addresses);
        meliesICO.addToWhitelist(1, addresses);
    }

    function test_AddedToWhitelistEventAlreadyWhitelisted() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        meliesICO.addToWhitelist(0, addresses);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AddedToWhitelist(0, addresses);
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_RemovedFromWhitelistEventSingleAddress() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        meliesICO.addToWhitelist(0, addresses);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RemovedFromWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);
    }

    function test_RemovedFromWhitelistEventMultipleAddresses() public {
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        meliesICO.addToWhitelist(0, addresses);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RemovedFromWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);
    }

    function test_RemovedFromWhitelistEventDifferentRounds() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addToWhitelist(1, addresses);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RemovedFromWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RemovedFromWhitelist(1, addresses);
        meliesICO.removeFromWhitelist(1, addresses);
    }

    function test_RemovedFromWhitelistEventNonWhitelistedAddress() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RemovedFromWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);
    }

    function test_TokensPurchasedEventWithUsdc() public {
        setupSaleRound();
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 1000e6, 10000e8);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();
    }

    function test_TokensPurchasedEventWithEth() public {
        setupSaleRound();
        vm.deal(user1, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 2000e6, 20000e8);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();
    }

    function test_TokensPurchasedEventAtMinimumPurchase() public {
        setupSaleRound();
        usdcToken.mint(user1, 100e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 100e6);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 100e6, 1000e8);
        meliesICO.buyWithUsdc(100e6);
        vm.stopPrank();
    }

    function test_TokensPurchasedEventAtMaximumPurchase() public {
        setupSaleRound();
        usdcToken.mint(user1, 10000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 10000e6);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 10000e6, 100000e8);
        meliesICO.buyWithUsdc(10000e6);
        vm.stopPrank();
    }

    function test_TokensPurchasedEventAcrossMultipleRounds() public {
        setupMultipleSaleRounds();
        usdcToken.mint(user1, 2000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);

        vm.warp(2);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 1000e6, 10000e8);
        meliesICO.buyWithUsdc(1000e6);

        vm.warp(block.timestamp + 8 days);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensPurchased(user1, 1000e6, 5000e8);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();
    }

    function test_UsdcWithdrawnEvent() public {
        setupSaleRound();
        usdcToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        meliesICO.endIco();

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.UsdcWithdrawn(admin, 1000e6);
        vm.prank(admin);
        meliesICO.withdrawUsdc();
    }

    function test_RefundedEvent() public {
        setupSaleRoundWithHighSoftCap();
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        meliesICO.endIco();

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.Refunded(user1, 1000e6);
        vm.prank(user1);
        meliesICO.refundForRound(0);
    }

    function test_SlippageToleranceUpdatedEvent() public {
        uint256 newSlippageTolerance = 100; // 1%

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.SlippageToleranceUpdated(newSlippageTolerance);
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(newSlippageTolerance);
    }

    function test_AllocationAddedEventWhenBuyingTokens() public {
        setupSaleRound();
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AllocationAdded(
            user1,
            10000e8,
            TGE_TIMESTAMP,
            30 days,
            180 days,
            0
        );
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();
    }

    function test_AllocationAddedEventForFiatPurchases() public {
        setupSaleRound();

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AllocationAdded(
            user1,
            10000e8,
            TGE_TIMESTAMP,
            30 days,
            180 days,
            0
        );
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 1000e6);
    }

    function test_AllocationAddedEventAcrossMultipleRounds() public {
        setupMultipleSaleRounds();
        vm.warp(2);
        usdcToken.mint(user1, 2000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AllocationAdded(
            user1,
            10000e8,
            TGE_TIMESTAMP,
            30 days,
            180 days,
            0
        );
        meliesICO.buyWithUsdc(1000e6);

        vm.warp(block.timestamp + 8 days);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.AllocationAdded(
            user1,
            5000e8,
            TGE_TIMESTAMP,
            90 days,
            240 days,
            1
        );
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();
    }

    function test_TokensClaimedEvent() public {
        setupSaleRoundAndPurchase();
        uint256 endRound = block.timestamp + 7 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        vm.prank(admin);
        meliesICO.endIco();

        vm.warp(endRound + 30 days + 1);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensClaimed(user1, 2500e8);
        vm.prank(user1);
        meliesICO.claimTokens();
    }

    function test_CurrentRoundEndTimeUpdatedEvent() public {
        setupSaleRound();
        uint256 newEndTime = block.timestamp + 14 days;

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.CurrentRoundEndTimeUpdated(0, newEndTime);
        vm.prank(admin);
        meliesICO.updateCurrentRoundEndTime(newEndTime);
    }

    function test_FutureRoundUpdatedEvent() public {
        setupMultipleSaleRounds();
        uint256 newStartTime = block.timestamp + 15 days;
        uint256 newEndTime = newStartTime + 7 days;
        vm.warp(2);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.FutureRoundUpdated(1);
        vm.prank(admin);
        meliesICO.updateFutureRound(
            1,
            newStartTime,
            newEndTime,
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
    }

    function test_RoundFundsWithdrawnEvent() public {
        setupSaleRound();
        usdcToken.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(100_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        meliesICO.endIco();

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RoundFundsWithdrawn(0, 100_000e6);
        vm.prank(admin);
        meliesICO.withdrawRoundFunds(0);
    }

    function test_RefundsAvailableForRoundEvent() public {
        setupSaleRoundWithHighSoftCap();
        usdcToken.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.RefundsAvailableForRound(0);
        vm.prank(admin);
        meliesICO.endIco();
    }

    function test_IcoEndedEvent() public {
        setupSaleRound();
        usdcToken.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(100_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.IcoEnded(true);
        vm.prank(admin);
        meliesICO.endIco();
    }

    function test_TokensRecoveredEvent() public {
        MockERC20 test_Token = new MockERC20("Test", "TEST");
        test_Token.mint(address(meliesICO), 1000e18);

        vm.expectEmit(true, false, false, true);
        emit IMeliesICO.TokensRecovered(address(test_Token), admin, 1000e18);
        vm.prank(admin);
        meliesICO.recoverTokens(address(test_Token), 1000e18);
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
            100_000e6,
            30 days,
            180 days,
            10,
            7
        );
    }

    function setupSaleRoundWithHighSoftCap() internal {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            900_000e6,
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
