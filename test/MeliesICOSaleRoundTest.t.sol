// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesICO.sol";
import "../src/interfaces/IMeliesICO.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

import {MockMeliesICO} from "../src/mock/MockMelies.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

contract MeliesICOSaleRoundTest is Test {
    MockMeliesICO public meliesICO;
    Melies public meliesToken;
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
        meliesToken = new Melies(admin);

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
            address(0x1234), // Temporary tokenDistributor address
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

    // Sale Round Management

    function test_AddSaleRound() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256 tokenPrice = 1e6; // 1 USDC per token
        uint256 maxCap = 1000000; // 1,000,000 USDC
        uint256 softCap = 100000; // 100,000 USDC
        uint256 minPurchase = 100; // 100 USDC
        uint256 maxPurchase = 10000; // 10,000 USDC
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 180 days;
        uint256 tgeReleasePercentage = 10; // 10% TGE release

        vm.prank(admin);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            tokenPrice,
            maxCap,
            softCap,
            minPurchase,
            maxPurchase,
            cliffDuration,
            vestingDuration,
            tgeReleasePercentage
        );

        (
            uint256 roundStartTime,
            uint256 roundEndTime,
            uint256 roundTokenPrice,
            uint256 roundMaxCap,
            uint256 roundSoftCap,
            uint256 roundMinPurchase,
            uint256 roundMaxPurchase,
            ,
            ,
            ,
            ,
            uint256 roundCliffDuration,
            uint256 roundVestingDuration,
            uint256 roundTgeReleasePercentage
        ) = meliesICO.saleRounds(0);

        assertEq(roundStartTime, startTime);
        assertEq(roundEndTime, endTime);
        assertEq(roundTokenPrice, tokenPrice);
        assertEq(roundMaxCap, maxCap);
        assertEq(roundSoftCap, softCap);
        assertEq(roundMinPurchase, minPurchase);
        assertEq(roundMaxPurchase, maxPurchase);
        assertEq(roundCliffDuration, cliffDuration);
        assertEq(roundVestingDuration, vestingDuration);
        assertEq(roundTgeReleasePercentage, tgeReleasePercentage);
    }

    function test_AddMultipleSaleRounds() public {
        uint256 startTime = block.timestamp + 1 days;

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(admin);
            meliesICO.addSaleRound(
                startTime + (i * 7 days),
                startTime + ((i + 1) * 7 days),
                1e6 + (i * 1e5),
                1000000,
                100000,
                100,
                10000,
                30 days,
                180 days,
                10 // 10% TGE release
            );
        }

        (uint256 round0StartTime, , , , , , , , , , , , , ) = meliesICO
            .saleRounds(0);
        (uint256 round1StartTime, , , , , , , , , , , , , ) = meliesICO
            .saleRounds(1);
        (uint256 round2StartTime, , , , , , , , , , , , , ) = meliesICO
            .saleRounds(2);

        assertEq(round0StartTime, startTime);
        assertEq(round1StartTime, startTime + 7 days);
        assertEq(round2StartTime, startTime + 14 days);
    }

    function test_AddSaleRoundWithInvalidParameters() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime - 1; // Invalid: end time before start time

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.InvalidTimeRange.selector);
        meliesICO.addSaleRound(
            startTime,
            endTime,
            1e6,
            1000000,
            100000,
            100,
            10000,
            30 days,
            180 days,
            10 // 10% TGE release
        );
    }

    function test_GetCurrentRound() public {
        setupMultipleSaleRounds();
        uint startTime = 2;

        // Check current round before start
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRound();

        // Check first round
        vm.warp(startTime + 1);
        IMeliesICO.SaleRound memory currentRound = meliesICO.getCurrentRound();
        assertEq(currentRound.tokenPrice, 0.1e6);

        // Check second round
        vm.warp(startTime + 7 days + 1);
        currentRound = meliesICO.getCurrentRound();
        assertEq(currentRound.tokenPrice, 0.2e6);

        // Check after all rounds
        vm.warp(startTime + 14 days + 1);
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRound();
    }

    function test_GetCurrentRoundId() public {
        setupMultipleSaleRounds();
        uint startTime = 2;

        // Check current round ID before start
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRoundId();

        // Check first round ID
        vm.warp(startTime + 1);
        assertEq(meliesICO.getCurrentRoundId(), 0);

        // Check second round ID
        vm.warp(startTime + 7 days + 1);
        assertEq(meliesICO.getCurrentRoundId(), 1);

        // Check after all rounds
        vm.warp(startTime + 14 days + 1);
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRoundId();
    }

    function test_UpdateFutureRound() public {
        uint256 startTime = 2;
        setupMultipleSaleRounds();

        // Warp to the first round
        vm.warp(startTime + 1 seconds);

        vm.prank(admin);
        meliesICO.updateFutureRound(1, 3000000e6, 30000e6);

        (
            ,
            ,
            ,
            uint256 updatedMaxCap,
            ,
            ,
            uint256 updatedMaxPurchase,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = meliesICO.saleRounds(1);

        assertEq(updatedMaxCap, 3000000e6);
        assertEq(updatedMaxPurchase, 30000e6);
    }

    function test_UpdateFutureRoundUnauthorized() public {
        setupMultipleSaleRounds();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.updateFutureRound(1, 3000000e6, 30000e6);
    }

    function test_UpdatePastOrCurrentRound() public {
        uint256 startTime = 2;
        setupMultipleSaleRounds();

        vm.warp(startTime + 1);

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.CannotModifyPastOrCurrentRound.selector);
        meliesICO.updateFutureRound(0, 3000000e6, 30000e6);
    }

    function test_RoundTransitions() public {
        uint256 startTime = 2;
        uint256 middleTime = 2 + 7 days;
        uint256 endTime = 2 + 14 days;
        setupMultipleSaleRounds();

        // Before first round
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRoundId();

        // First round
        vm.warp(startTime);
        uint256 currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);

        // End of round 1
        vm.warp(middleTime - 1 seconds);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);

        // Second round
        vm.warp(middleTime);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 1);

        // End of round 2
        vm.warp(endTime - 1 seconds);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 1);

        // After all rounds
        vm.warp(endTime);
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.getCurrentRoundId();
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
            10
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
            10
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
    }
}
