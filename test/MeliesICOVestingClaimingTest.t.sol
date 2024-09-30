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

contract MeliesICOVestingClaimingTest is Test {
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

    // Vesting and Token Claiming

    function test_VestingScheduleBasic() public {
        // Setup sale round and purchase
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        uint256 cliffRound = 30 days;
        uint256 vestingRound = 180 days;
        setupTgeTimestamp(endRound);

        // Check claimable amount before cliff
        vm.warp(endRound + cliffRound - 1);

        (
            uint256 claimableAmount,
            uint256 tgeReleaseAmount,
            uint256 newLastClaimTimestamp
        ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 1000e8); //10% of 10000 = 1000
        assertEq(tgeReleaseAmount, 1000e8); //10% of 10000 = 1000

        // Check claimable amount after cliff but before full vesting
        vm.warp(endRound + cliffRound + 1);
        (claimableAmount, tgeReleaseAmount, newLastClaimTimestamp) = meliesICO
            .getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 2500e8); //1/6 of 10000 = 1500 + 1000 (tge) = 2500
        assertEq(tgeReleaseAmount, 1000e8); //10% of 10000 = 1000

        // Check claimable amount after full vesting
        vm.warp(endRound + cliffRound + vestingRound + 1);
        (claimableAmount, tgeReleaseAmount, newLastClaimTimestamp) = meliesICO
            .getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 10_000e8); // 100% of 10000 = 10000
        assertEq(tgeReleaseAmount, 1000e8); // 10% of 10000 = 1000
    }

    function test_TokenClaimingPartial() public {
        // Setup sale round and purchase
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        uint256 cliffRound = 30 days;
        uint256 vestingRound = 180 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Fast forward to middle of vesting period
        vm.warp(endRound + cliffRound + vestingRound / 2);

        uint256 initialBalance = meliesToken.balanceOf(user1);
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);

        vm.prank(user1);
        meliesICO.claimTokens();

        uint256 finalBalance = meliesToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, claimableAmount);

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.claimedAmount, claimableAmount);
    }

    function test_TokenClaimingMultipleRounds() public {
        // Setup two sale rounds with different vesting schedules
        setupMultipleSaleRoundAndPurchase();
        uint256 endRound = 1 + 14 days;
        uint256 cliffRound2 = endRound + 90 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Fast forward to a point where some tokens are claimable from both rounds
        vm.warp(cliffRound2 + 1);

        uint256 initialBalance = meliesToken.balanceOf(user1);

        (uint256 claimableAmount1, uint256 tgeReleaseAmount1, ) = meliesICO
            .getClaimableAmount(user1, 0);

        (uint256 claimableAmount2, uint256 tgeReleaseAmount2, ) = meliesICO
            .getClaimableAmount(user1, 1);

        assertEq(tgeReleaseAmount1, 2_000e8); // 10% of 20_000 = 2000
        assertEq(claimableAmount1, 11_000e8); // 3 * 18_000 / 6 = 9000 + 2000 (tge) = 11_000
        assertEq(tgeReleaseAmount2, 0); // 0% of 5_000 = 0
        assertEq(claimableAmount2, 625e8); // 1 * 5_000 / 8 = 625
        vm.prank(user1);
        meliesICO.claimTokens();

        uint256 finalBalance = meliesToken.balanceOf(user1);
        uint256 claimedAmount = finalBalance - initialBalance;

        assertEq(claimedAmount, 11_625e8); // 2000 + 9000 + 625
    }

    function test_ClaimingBeforeICOEnds() public {
        setupSaleRoundAndPurchase();

        // Fast forward time
        vm.warp(block.timestamp + 210 days);

        // Attempt to claim tokens before ICO ends
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.IcoNotEndedYet.selector);
        meliesICO.claimTokens();
    }

    function test_VestingWithNoCliff() public {
        // Setup sale round with no cliff
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            100_000e6,
            0, // No cliff
            180 days,
            10, // TGE release percentage
            3 days // Lock duration
        );
        setupTgeTimestamp(endTime);

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        usdcToken.mint(user2, 100_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6); // 10_000 tokens
        vm.stopPrank();
        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(100_000e6); // 1_000_000 tokens
        vm.stopPrank();
        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Check claimable amount immediately after purchase
        vm.warp(endTime + 1);
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(
            claimableAmount,
            2_500e8 // 10% of 10_000 = 1_000 + 1 * 9_000 / 6 = 1_500
        );
    }

    function test_TokenClaimingFull() public {
        // Setup sale round with cliff equal to vesting duration
        uint256 startTime = block.timestamp;
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
            60 days,
            0, // TGE release percentage
            3 days // Lock duration
        );
        setupTgeTimestamp(endTime);

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        usdcToken.mint(user2, 100_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(100_000e6); // 1_000_000 tokens
        vm.stopPrank();

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Check claimable amount after cliff/vesting ends
        vm.warp(endTime + 180 days);
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 10_000e8);
    }

    function test_ClaimingMultipleTimesDuringVesting() public {
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        uint256 cliffRound = 30 days;
        uint256 vestingRound = 180 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Claim at 25% vesting
        vm.warp(endRound + cliffRound + vestingRound / 4);
        uint256 initialBalance = meliesToken.balanceOf(user1);

        vm.prank(user1);
        meliesICO.claimTokens();
        uint256 firstClaimAmount = meliesToken.balanceOf(user1) -
            initialBalance;
        assertEq(
            firstClaimAmount,
            4_000e8 // 10% of 10_000 = 1_000 + 2 * 9_000 / 6 = 4_000
        );

        // Check that claiming again will not work
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 0);

        // Claim at 50% vesting
        vm.warp(endRound + cliffRound + vestingRound / 2 + 1);

        initialBalance = meliesToken.balanceOf(user1);
        vm.prank(user1);
        meliesICO.claimTokens();
        uint256 secondClaimAmount = meliesToken.balanceOf(user1) -
            initialBalance;
        assertEq(
            secondClaimAmount,
            3_000e8 // 2 * 9_000 / 6 = 3_000e8
        );

        // Verify total claimed amount
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.claimedAmount, 7_000e8);

        // Claim at 100% vesting
        vm.warp(endRound + cliffRound + vestingRound + 1);

        initialBalance = meliesToken.balanceOf(user1);
        vm.prank(user1);
        meliesICO.claimTokens();
        uint256 thirdClaimAmount = meliesToken.balanceOf(user1) -
            initialBalance;
        assertEq(
            thirdClaimAmount,
            3_000e8 // 2 * 9_000 / 6 = 3_000e8
        );

        // Verify total claimed amount
        allocation = meliesICO.getAllocationDetails(user1, 0);
        assertEq(allocation.claimedAmount, 10_000e8);
    }

    function test_VestingForMultipleUsers() public {
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        uint256 cliffRound = 30 days;
        uint256 vestingRound = 180 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Fast forward to middle of vesting
        vm.warp(endRound + cliffRound + vestingRound / 2);

        // Check claimable amounts
        (uint256 user1Claimable, , ) = meliesICO.getClaimableAmount(user1, 0);
        (uint256 user2Claimable, , ) = meliesICO.getClaimableAmount(user2, 0);
        assertEq(
            user1Claimable,
            7000e8, // 10% of 10_000 = 1_000 + 4 * 9_000 / 6 = 7_000
            "User1 should have claimed about 7000 tokens"
        );
        assertEq(
            user2Claimable,
            700_000e8, // 10% of 1_000_000 = 100_000 + 4 * 900_000 / 6 = 700_000
            "User2 should have claimed about 70000 tokens"
        );

        // Users claim tokens
        vm.prank(user1);
        meliesICO.claimTokens();
        vm.prank(user2);
        meliesICO.claimTokens();

        // Verify claimed amounts
        assertEq(meliesToken.balanceOf(user1), 7000e8);
        assertEq(meliesToken.balanceOf(user2), 700_000e8);
    }

    function test_TokenClaimingWithLongPeriod() public {
        // Setup sale round with cliff equal to vesting duration
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            100_000e6,
            300 days,
            600 days,
            0, // TGE release percentage
            3 days // Lock duration
        );
        setupTgeTimestamp(endTime);

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        usdcToken.mint(user2, 100_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 100_000e6);
        meliesICO.buyWithUsdc(100_000e6); // 1_000_000 tokens
        vm.stopPrank();

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Check claimable amount after cliff/vesting ends
        vm.warp(endTime + 900 days);
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 10_000e8);
    }

    function test_VestingWithLargeTokenAmounts() public {
        // Setup sale round with a very low token price
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.001e6, // $0.001 per token
            1_000_000e6,
            100_000e6,
            100e6,
            1_000_000e6,
            30 days,
            180 days,
            10, // TGE release percentage
            3 days // Lock duration
        );
        setupTgeTimestamp(endTime);

        // User buys a large amount of tokens
        usdcToken.mint(user1, 1_000_000e6);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1_000_000e6);
        meliesICO.buyWithUsdc(1_000_000e6); // 1_000_000_000 tokens
        vm.stopPrank();

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Fast forward to middle of vesting
        vm.warp(endTime + 30 days + 180 days / 2);

        // Check claimable amount
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(
            claimableAmount,
            700_000_000e8 // 10% of 1_000_000_000 = 100_000_000 + 4 * 900_000_000 / 6 = 700_000_000
        );

        // Claim tokens
        vm.prank(user1);
        meliesICO.claimTokens();

        // Verify claimed amount
        assertEq(meliesToken.balanceOf(user1), 700_000_000e8);

        // Fast forward to end of vesting
        vm.warp(endTime + 30 days + 180 days + 1);

        // Check claimable amount
        (claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(claimableAmount, 300_000_000e8);

        // Claim tokens
        vm.prank(user1);
        meliesICO.claimTokens();

        // Verify claimed amount
        assertEq(meliesToken.balanceOf(user1), 1_000_000_000e8);
    }

    function test_VestingWithMultiplePurchasesInSameRound() public {
        // User2 makes multiple purchases (10 x 10_000e6 USDC = 1_000_000e8 tokens)
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        uint256 cliffRound = 30 days;
        uint256 vestingRound = 180 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Fast forward to end of vesting
        vm.warp(endRound + cliffRound + vestingRound + 1);

        // Check claimable amount
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user2, 0);
        assertEq(claimableAmount, 1_000_000e8);

        // Claim tokens
        vm.prank(user2);
        meliesICO.claimTokens();

        // Verify claimed amount
        assertEq(meliesToken.balanceOf(user2), 1_000_000e8);
    }

    function test_RefundEffectOnVesting() public {
        // Setup sale round with high soft cap
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            900_000e6, // High soft cap
            100e6,
            10_000e6,
            30 days,
            180 days,
            10, // TGE release percentage
            3 days // Lock duration
        );

        // User buys tokens
        usdcToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // End ICO without reaching soft cap
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // User requests refund
        vm.prank(user1);
        meliesICO.refundForRound(0);

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

        // Verify no tokens are claimable
        (uint256 claimableAmount, , ) = meliesICO.getClaimableAmount(user1, 0);
        assertEq(
            claimableAmount,
            0,
            "No tokens should be claimable after refund"
        );
    }

    function test_ClaimingAfterContractPauseAndUnpause() public {
        setupSaleRoundAndPurchase();
        uint256 endRound = 1 + 7 days;
        uint256 cliffRound = 30 days;
        uint256 vestingRound = 180 days;
        setupTgeTimestamp(endRound);
        vm.warp(endRound);

        // End ICO and enable claiming
        vm.prank(admin);
        meliesICO.endIco();

        // Fast forward to after vesting period
        vm.warp(endRound + cliffRound + vestingRound + 1);

        // Pause the contract
        vm.prank(pauser);
        meliesToken.pause();

        // Attempt to claim (should fail)
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        vm.prank(user1);
        meliesICO.claimTokens();

        // Unpause the contract
        vm.prank(pauser);
        meliesToken.unpause();

        // Successfully claim tokens
        vm.prank(user1);
        meliesICO.claimTokens();

        // Verify claimed amount
        assertEq(
            meliesToken.balanceOf(user1),
            10_000e8,
            "Should have claimed all tokens after unpause"
        );
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
