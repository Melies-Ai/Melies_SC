// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesICO.sol";
import "../src/interfaces/IMeliesICO.sol";
import "../src/Melies.sol";
import "../src/MeliesTokenDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

import {MockMeliesICO} from "../src/mock/MockMelies.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

contract MeliesICOPurchasesTest is Test {
    MockMeliesICO public meliesICO;
    MeliesTokenDistributor public tokenDistributor;
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

        // Deploy TokenDistributor first
        tokenDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            TGE_TIMESTAMP,
            admin,
            address(0x111), // Community
            address(0x222), // Treasury
            address(0x333), // Partners
            address(0x444), // Team
            address(0x555), // Liquidity
            address(0x666) // AI Systems
        );

        // Deploy MeliesICO with real tokenDistributor
        meliesICO = new MockMeliesICO(
            address(meliesToken),
            address(tokenDistributor),
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

        // Grant MINTER_ROLE to contracts
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
        meliesToken.grantRole(
            meliesToken.MINTER_ROLE(),
            address(tokenDistributor)
        );

        // Grant ICO_ROLE to ICO contract in TokenDistributor
        tokenDistributor.grantRole(
            tokenDistributor.ICO_ROLE(),
            address(meliesICO)
        );
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

    // Token Purchases
    function test_BuyWithEth() public {
        // Setup sale round
        setupSaleRound();

        // User buys tokens with 1 ETH
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 2000e6); // 2000 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 20_000e8, "Seed"); // 2000 USDC / 0.1 USDC per token = 20000 tokens
    }

    function test_BuyWithEthExactMinimumPurchase() public {
        // Setup sale round
        setupSaleRound();

        // User buys tokens with 0.05 ETH (100 USDC, exact minimum)
        vm.deal(user1, 0.05 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 0.05 ether}();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 100e6); // 100 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 1000e8, "Seed"); // 100 USDC / 0.1 USDC per token = 1000 tokens
    }

    function test_BuyWithEthExactMaximumPurchase() public {
        // Setup sale round
        setupSaleRound();

        // User buys tokens with 5 ETH (10,000 USDC, exact maximum)
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 5 ether}();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 10_000e6); // 10,000 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 100_000e8, "Seed"); // 10,000 USDC / 0.1 USDC per token = 100,000 tokens
    }

    function test_BuyWithEthExceedingRoundCap() public {
        // Add a sale round
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        uint256 tokenPrice = 0.1e6; // $0.1 per token
        uint256 maxCap = 1_000_000e6; // 1 million USDC
        uint256 softCap = 100_000e6; // 100k USDC
        uint256 minPurchase = 100e6; // 100 USDC
        uint256 maxPurchase = 2_000_000e6; // 2M USDC - to not trigger max purchase
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 180 days;
        uint256 tgeReleasePercentage = 10;

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

        // User buys tokens with 500 ETH (1,000,000 USDC, exceeding round cap)
        vm.deal(user1, 501 ether);
        vm.expectRevert(IMeliesICO.RoundCapExceeded.selector);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 501 ether}();
    }

    function test_BuyWithEthBelowMinimum() public {
        // Setup sale round
        setupSaleRound();

        // User tries to buy tokens with 0.04 ETH (80 USDC, below minimum)
        vm.deal(user1, 0.04 ether);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 0.04 ether}();
    }

    function test_BuyWithEthAboveMaximum() public {
        // Setup sale round
        setupSaleRound();

        // User tries to buy tokens with 5.001 ETH (10,002 USDC, just above maximum)
        vm.deal(user1, 5.001 ether);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 5.001 ether}();
    }

    function test_BuyWithEthNoActiveRound() public {
        // Try to buy tokens when no round is active
        vm.deal(user1, 1 ether);
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();
    }

    function test_BuyWithEthInvalidEthUsdPrice() public {
        // Setup sale round
        setupSaleRound();

        ethUsdPriceFeed.updateAnswer(0); // Set price to 0, which is invalid

        // User tries to buy tokens with 1 ETH
        vm.deal(user1, 1 ether);
        vm.expectRevert(IMeliesICO.InvalidEthUsdPrice.selector);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();
    }

    function test_BuyWithEthMultiplePurchases() public {
        // Setup sale round
        setupSaleRound();

        // User buys tokens with 0.5 ETH twice
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        meliesICO.buyWithEth{value: 0.5 ether}();
        meliesICO.buyWithEth{value: 0.5 ether}();
        vm.stopPrank();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 2000e6); // 2000 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 20_000e8, "Seed"); // 2000 USDC / 0.1 USDC per token = 20000 tokens
    }

    function test_BuyWithEthMultipleRounds() public {
        uint256 startTimeRound1 = 2;
        uint256 startTimeRound2 = 2 + 7 days;
        setupMultipleSaleRounds();

        vm.warp(startTimeRound1 + 1);

        uint256 currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);

        // User buys tokens with 0.5 ETH in the first round
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 0.5 ether}();

        // Move to the second round
        vm.warp(startTimeRound2 + 1);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 1);

        // User buys tokens with 0.5 ETH in the second round
        vm.prank(user1);
        meliesICO.buyWithEth{value: 0.5 ether}();

        // Check user's allocation for both rounds in ICO (USD tracking)
        IMeliesICO.Allocation memory allocation1 = meliesICO
            .getAllocationDetails(user1, 0);
        IMeliesICO.Allocation memory allocation2 = meliesICO
            .getAllocationDetails(user1, 1);

        assertEq(allocation1.totalUsdcAmount, 1000e6); // 1000 USDC
        assertEq(allocation2.totalUsdcAmount, 1000e6); // 1000 USDC

        // Check user's token allocations in TokenDistributor
        assertTokenAllocation(user1, 10_000e8, "Seed"); // 1000 USDC / 0.1 USDC per token = 10000 tokens
        assertTokenAllocation(user1, 5000e8, "Private Sale"); // 1000 USDC / 0.2 USDC per token = 5000 tokens
    }

    function test_BuyWithEthAfterIcoEnded() public {
        // Setup sale round
        setupSaleRound();

        // End the ICO
        vm.prank(admin);
        meliesICO.endIco();

        // User tries to buy tokens with ETH after ICO has ended
        vm.deal(user1, 1 ether);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();
    }

    function test_BuyWithEthRefundScenario() public {
        // Setup sale round with a high soft cap
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
            10
        );

        // User buys tokens with 1 ETH
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();

        // End ICO
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // Record USDC balance before refund
        uint256 usdcBalanceBefore = usdcToken.balanceOf(user1);

        // User requests refund
        vm.prank(user1);
        meliesICO.refund();

        // Check that user received their USDC back
        uint256 usdcBalanceAfter = usdcToken.balanceOf(user1);
        assertEq(usdcBalanceAfter - usdcBalanceBefore, 2000e6); // 2000 USDC (equivalent to 1 ETH)
    }

    function test_RefundFailsWhenSoftCapReached() public {
        // Setup sale round with a low soft cap
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        meliesICO.addSaleRound(
            startTime,
            endTime,
            0.1e6,
            1_000_000e6,
            1_000e6, // Low soft cap (1,000 USDC)
            100e6,
            10_000e6,
            30 days,
            180 days,
            10
        );

        // User buys tokens with 1 ETH (2000 USDC, which exceeds the soft cap)
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();

        // End ICO
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // User attempts to request a refund
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.RefundNotAvailable.selector);
        meliesICO.refund();

        // Check that user's USDC balance hasn't changed
        assertEq(usdcToken.balanceOf(user1), 0);
    }

    function test_BuyWithUsdc() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        // User buys tokens with 1000 USDC
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 1000e6); // 1000 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 10_000e8, "Seed"); // 1000 USDC / 0.1 USDC per token = 10000 tokens
    }

    function test_BuyWithUsdcExactMinimumPurchase() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 100e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 100e6);

        // User buys tokens with 100 USDC (exact minimum)
        vm.prank(user1);
        meliesICO.buyWithUsdc(100e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 100e6); // 100 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 1000e8, "Seed"); // 100 USDC / 0.1 USDC per token = 1000 tokens
    }

    function test_BuyWithUsdcExactMaximumPurchase() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 10_000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 10_000e6);

        // User buys tokens with 10,000 USDC (exact maximum)
        vm.prank(user1);
        meliesICO.buyWithUsdc(10_000e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 10_000e6); // 10,000 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 100_000e8, "Seed"); // 10,000 USDC / 0.1 USDC per token = 100,000 tokens
    }

    function test_BuyWithUsdcBelowMinimum() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 99e6); // Mint 99 USDC, which is below the minimum purchase

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 99e6);

        // User tries to buy tokens with 99 USDC (below minimum)
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.buyWithUsdc(99e6);
    }

    function test_BuyWithUsdcAboveMaximum() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 10001e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 10001e6);

        // User tries to buy tokens with 15000 USDC (above maximum)
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        meliesICO.buyWithUsdc(10001e6);
    }

    function test_BuyWithUsdcExceedingRoundCap() public {
        // Add a sale round
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        uint256 tokenPrice = 0.1e6; // $0.1 per token
        uint256 maxCap = 1_000_000e6; // 1 million USDC
        uint256 softCap = 100_000e6; // 100k USDC
        uint256 minPurchase = 100e6; // 100 USDC
        uint256 maxPurchase = 2_000_000e6; // 2M USDC (high enough to not trigger maxPurchase error)
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 180 days;
        uint256 tgeReleasePercentage = 10;

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

        // Mint USDC to user1
        usdcToken.mint(user1, 1_000_001e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1_000_001e6);

        // User buys tokens with 1,000,001 USDC (exceeding round cap)
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.RoundCapExceeded.selector);
        meliesICO.buyWithUsdc(1_000_001e6);
    }

    function test_BuyWithUsdcNoActiveRound() public {
        // Mint USDC to user1
        usdcToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        // Try to buy tokens when no round is active
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.buyWithUsdc(1000e6);
    }

    function test_BuyWithUsdcInvalidUsdcAmount() public {
        // Setup sale round
        setupSaleRound();

        // Try to buy tokens with 0 USDC
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.UsdcAmountMustBeGreaterThanZero.selector);
        meliesICO.buyWithUsdc(0);
    }

    function test_BuyWithUsdcMultiplePurchases() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdcToken.mint(user1, 2000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);

        // User buys tokens with 1000 USDC twice
        vm.startPrank(user1);
        meliesICO.buyWithUsdc(1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 2000e6); // 2000 USDC

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 20000e8, "Seed"); // 2000 USDC / 0.1 USDC per token = 20000 tokens
    }

    function test_BuyWithUsdcMultipleRounds() public {
        uint256 startTimeRound1 = 2;
        uint256 startTimeRound2 = 2 + 7 days;
        setupMultipleSaleRounds();

        vm.warp(startTimeRound1 + 1);

        uint256 currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);

        // Mint USDC to user1
        usdcToken.mint(user1, 2000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 2000e6);

        // User buys tokens with 1000 USDC in the first round
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // Move to the second round
        vm.warp(startTimeRound2 + 1);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 1);

        // User buys tokens with 1000 USDC in the second round
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // Check user's allocation for both rounds in ICO (USD tracking)
        IMeliesICO.Allocation memory allocation1 = meliesICO
            .getAllocationDetails(user1, 0);
        IMeliesICO.Allocation memory allocation2 = meliesICO
            .getAllocationDetails(user1, 1);

        assertEq(allocation1.totalUsdcAmount, 1000e6); // 1000 USDC
        assertEq(allocation2.totalUsdcAmount, 1000e6); // 1000 USDC

        // Check user's token allocations in TokenDistributor
        assertTokenAllocation(user1, 10000e8, "Seed"); // 1000 USDC / 0.1 USDC per token = 10000 tokens
        assertTokenAllocation(user1, 5000e8, "Private Sale"); // 1000 USDC / 0.2 USDC per token = 5000 tokens
    }

    function test_BuyWithUsdcAfterIcoEnded() public {
        // Setup sale round
        setupSaleRound();

        // End the ICO
        vm.prank(admin);
        meliesICO.endIco();

        // Mint USDC to user1
        usdcToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        // User tries to buy tokens with USDC after ICO has ended
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.buyWithUsdc(1000e6);
    }

    function test_BuyWithUsdcRefundScenario() public {
        // Setup sale round with a high soft cap
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
            10
        );

        // Mint USDC to user1
        usdcToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);

        // User buys tokens with 1000 USDC
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        // End ICO
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // User requests refund
        vm.prank(user1);
        meliesICO.refund();

        // Check that user received their USDC back
        assertEq(usdcToken.balanceOf(user1), 1000e6);
    }

    function test_BuyWithUsdt() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDC to user1
        usdtToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDC
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 1000e6);

        // User buys tokens with 1000 USDC
        vm.prank(user1);
        meliesICO.buyWithUsdt(1000e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdtAmount, 1000e6); // 1000 USDT

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 10_000e8, "Seed"); // 1000 USDT / 0.1 USDT per token = 10000 tokens
    }

    function test_BuyWithUsdtExactMinimumPurchase() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDT to user1
        usdtToken.mint(user1, 100e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 100e6);

        // User buys tokens with 100 USDT (exact minimum)
        vm.prank(user1);
        meliesICO.buyWithUsdt(100e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdtAmount, 100e6); // 100 USDT

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 1000e8, "Seed"); // 100 USDT / 0.1 USDT per token = 1000 tokens
    }

    function test_BuyWithUsdtExactMaximumPurchase() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDT to user1
        usdtToken.mint(user1, 10_000e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 10_000e6);

        // User buys tokens with 10,000 USDT (exact maximum)
        vm.prank(user1);
        meliesICO.buyWithUsdt(10_000e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdtAmount, 10_000e6); // 10,000 USDT

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 100_000e8, "Seed"); // 10,000 USDT / 0.1 USDT per token = 100,000 tokens
    }

    function test_BuyWithUsdtBelowMinimum() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDT to user1
        usdtToken.mint(user1, 99e6); // Mint 99 USDT, which is below the minimum purchase

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 99e6);

        // User tries to buy tokens with 99 USDT (below minimum)
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.buyWithUsdt(99e6);
    }

    function test_BuyWithUsdtAboveMaximum() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDT to user1
        usdtToken.mint(user1, 10001e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 10001e6);

        // User tries to buy tokens with 15000 USDT (above maximum)
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        meliesICO.buyWithUsdt(10001e6);
    }

    function test_BuyWithUsdtExceedingRoundCap() public {
        // Add a sale round
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        uint256 tokenPrice = 0.1e6; // $0.1 per token
        uint256 maxCap = 1_000_000e6; // 1 million USDT
        uint256 softCap = 100_000e6; // 100k USDT
        uint256 minPurchase = 100e6; // 100 USDT
        uint256 maxPurchase = 2_000_000e6; // 2M USDT (high enough to not trigger maxPurchase error)
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 180 days;
        uint256 tgeReleasePercentage = 10;

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

        // Mint USDT to user1
        usdtToken.mint(user1, 1_000_001e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 1_000_001e6);

        // User buys tokens with 1,000,001 USDT (exceeding round cap)
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.RoundCapExceeded.selector);
        meliesICO.buyWithUsdt(1_000_001e6);
    }

    function test_BuyWithUsdtNoActiveRound() public {
        // Mint USDT to user1
        usdtToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 1000e6);

        // Try to buy tokens when no round is active
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.NoActiveRound.selector);
        meliesICO.buyWithUsdt(1000e6);
    }

    function test_BuyWithUsdtInvalidUsdtAmount() public {
        // Setup sale round
        setupSaleRound();

        // Try to buy tokens with 0 USDT
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.UsdtAmountMustBeGreaterThanZero.selector);
        meliesICO.buyWithUsdt(0);
    }

    function test_BuyWithUsdtMultiplePurchases() public {
        // Setup sale round
        setupSaleRound();

        // Mint USDT to user1
        usdtToken.mint(user1, 2000e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 2000e6);

        // User buys tokens with 1000 USDT twice
        vm.startPrank(user1);
        meliesICO.buyWithUsdt(1000e6);
        meliesICO.buyWithUsdt(1000e6);
        vm.stopPrank();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdtAmount, 2000e6); // 2000 USDT

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 20000e8, "Seed"); // 2000 USDT / 0.1 USDT per token = 20000 tokens
    }

    function test_BuyWithUsdtMultipleRounds() public {
        uint256 startTimeRound1 = 2;
        uint256 startTimeRound2 = 2 + 7 days;
        setupMultipleSaleRounds();

        vm.warp(startTimeRound1 + 1);

        uint256 currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);

        // Mint USDT to user1
        usdtToken.mint(user1, 2000e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 2000e6);

        // User buys tokens with 1000 USDT in the first round
        vm.prank(user1);
        meliesICO.buyWithUsdt(1000e6);

        // Move to the second round
        vm.warp(startTimeRound2 + 1);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 1);

        // User buys tokens with 1000 USDT in the second round
        vm.prank(user1);
        meliesICO.buyWithUsdt(1000e6);

        // Check user's allocation for both rounds in ICO (USD tracking)
        IMeliesICO.Allocation memory allocation1 = meliesICO
            .getAllocationDetails(user1, 0);
        IMeliesICO.Allocation memory allocation2 = meliesICO
            .getAllocationDetails(user1, 1);

        assertEq(allocation1.totalUsdtAmount, 1000e6); // 1000 USDT
        assertEq(allocation2.totalUsdtAmount, 1000e6); // 1000 USDT

        // Check user's token allocations in TokenDistributor
        assertTokenAllocation(user1, 10000e8, "Seed"); // 1000 USDT / 0.1 USDT per token = 10000 tokens
        assertTokenAllocation(user1, 5000e8, "Private Sale"); // 1000 USDT / 0.2 USDT per token = 5000 tokens
    }

    function test_BuyWithUsdtAfterIcoEnded() public {
        // Setup sale round
        setupSaleRound();

        // End the ICO
        vm.prank(admin);
        meliesICO.endIco();

        // Mint USDT to user1
        usdtToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 1000e6);

        // User tries to buy tokens with USDT after ICO has ended
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.buyWithUsdt(1000e6);
    }

    function test_BuyWithUsdtRefundScenario() public {
        // Setup sale round with a high soft cap
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
            10
        );

        // Mint USDT to user1
        usdtToken.mint(user1, 1000e6);

        // Approve ICO contract to spend user's USDT
        vm.prank(user1);
        usdtToken.approve(address(meliesICO), 1000e6);

        // User buys tokens with 1000 USDT
        vm.prank(user1);
        meliesICO.buyWithUsdt(1000e6);

        // End ICO
        vm.warp(endTime + 1);
        vm.prank(admin);
        meliesICO.endIco();

        // User requests refund
        vm.prank(user1);
        meliesICO.refund();

        // Check that user received their USDT back
        assertEq(usdtToken.balanceOf(user1), 1000e6);
    }

    function test_AddFiatPurchase() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 1000e6);

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 1000e6); // 1000 USD (fiat treated as USDC equivalent)

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 10_000e8, "Seed"); // 1000 USD / 0.1 USD per token = 10000 tokens
    }

    function test_FiatPurchaseExactMinimum() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 100e6); // 100 USDC, exact minimum

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 100e6); // 100 USD (fiat treated as USDC equivalent)

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 1000e8, "Seed"); // 100 USD / 0.1 USD per token = 1000 tokens
    }

    function test_FiatPurchaseExactMaximum() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 10_000e6); // 10,000 USDC, exact maximum

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 10_000e6); // 10,000 USD (fiat treated as USDC equivalent)

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 100_000e8, "Seed"); // 10,000 USD / 0.1 USD per token = 100,000 tokens
    }

    function test_FiatPurchaseBelowMinimum() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.addFiatPurchase(user1, 99e6); // 99 USDC, below minimum
    }

    function test_FiatPurchaseAboveMaximum() public {
        setupSaleRound();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        meliesICO.addFiatPurchase(user1, 10_001e6); // 10,001 USDC, above maximum
    }

    function test_FiatPurchaseMultiplePurchases() public {
        setupSaleRound();

        vm.startPrank(admin);
        meliesICO.addFiatPurchase(user1, 500e6); // 500 USDC
        meliesICO.addFiatPurchase(user1, 300e6); // 300 USDC
        vm.stopPrank();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 800e6); // 800 USD (fiat treated as USDC equivalent)

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user1, 8000e8, "Seed"); // 800 USD / 0.1 USD per token = 8000 tokens
    }

    function test_FiatPurchaseMultipleRounds() public {
        uint256 startTimeRound1 = 2;
        uint256 startTimeRound2 = 2 + 7 days;
        setupMultipleSaleRounds();

        vm.warp(startTimeRound1 + 1);

        uint256 currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 0);

        // Admin adds fiat purchase for user1 in the first round
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 1000e6); // 1000 USDC equivalent

        // Move to the second round
        vm.warp(startTimeRound2 + 1);
        currentRoundId = meliesICO.getCurrentRoundId();
        assertEq(currentRoundId, 1);

        // Admin adds fiat purchase for user1 in the second round
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 1000e6); // 1000 USDC equivalent

        // Check user's allocation for both rounds in ICO (USD tracking)
        IMeliesICO.Allocation memory allocation1 = meliesICO
            .getAllocationDetails(user1, 0);
        IMeliesICO.Allocation memory allocation2 = meliesICO
            .getAllocationDetails(user1, 1);

        assertEq(allocation1.totalUsdcAmount, 1000e6); // 1000 USD (fiat treated as USDC equivalent)
        assertEq(allocation2.totalUsdcAmount, 1000e6); // 1000 USD (fiat treated as USDC equivalent)

        // Check user's token allocations in TokenDistributor
        assertTokenAllocation(user1, 10000e8, "Seed"); // 1000 USD / 0.1 USD per token = 10000 tokens
        assertTokenAllocation(user1, 5000e8, "Private Sale"); // 1000 USD / 0.2 USD per token = 5000 tokens
    }

    function test_FiatPurchaseExceedingRoundCap() public {
        // Add a sale round
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        uint256 tokenPrice = 0.1e6; // $0.1 per token
        uint256 maxCap = 1_000_000e6; // 1 million USDC
        uint256 softCap = 100_000e6; // 100k USDC
        uint256 minPurchase = 100e6; // 100 USDC
        uint256 maxPurchase = 2_000_000e6; // 2M USDC (high enough to not trigger maxPurchase error)
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 180 days;
        uint256 tgeReleasePercentage = 10;

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

        // Fill up most of the cap
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 999_900e6); // 999,900 USDC

        // Try to exceed the cap
        vm.expectRevert(IMeliesICO.RoundCapExceeded.selector);
        vm.prank(admin);
        meliesICO.addFiatPurchase(user2, 101e6); // 101 USDC, exceeding cap
    }

    function test_FiatPurchaseFillingRoundCap() public {
        // Add a sale round
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 7 days;
        uint256 tokenPrice = 0.1e6; // $0.1 per token
        uint256 maxCap = 1_000_000e6; // 1 million USDC
        uint256 softCap = 100_000e6; // 100k USDC
        uint256 minPurchase = 100e6; // 100 USDC
        uint256 maxPurchase = 2_000_000e6; // 2M USDC (high enough to not trigger maxPurchase error)
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 180 days;
        uint256 tgeReleasePercentage = 10;

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

        // Fill up most of the cap
        vm.prank(admin);
        meliesICO.addFiatPurchase(user1, 999_900e6); // 999,900 USDC

        // Fill the remaining cap exactly
        vm.prank(admin);
        meliesICO.addFiatPurchase(user2, 100e6); // 100 USDC, filling the cap

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user2, 0);
        assertEq(allocation.totalUsdcAmount, 100e6); // 100 USD (fiat treated as USDC equivalent)

        // Check user's token allocation in TokenDistributor
        assertTokenAllocation(user2, 1000e8, "Seed"); // 100 USD / 0.1 USD per token = 1000 tokens
    }

    function test_FiatPurchaseAfterIcoEnded() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.addFiatPurchase(user1, 1000e6);
    }

    function test_FiatPurchaseNonAdminAttempt() public {
        setupSaleRound();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.addFiatPurchase(user2, 1000e6);
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

    /**
     * @dev Helper function to get user's token allocation from TokenDistributor
     * @param user Address of the user
     * @param roundName Expected round name ("Seed", "Private Sale", "Public Sale")
     * @return totalAmount Total tokens allocated
     * @return claimedAmount Tokens already claimed
     */
    function getUserTokenAllocation(
        address user,
        string memory roundName
    ) internal view returns (uint256 totalAmount, uint256 claimedAmount) {
        uint256[] memory allocIndices = tokenDistributor
            .getAllocationsForBeneficiary(user);

        for (uint256 i = 0; i < allocIndices.length; i++) {
            (, , , , , string memory allocName, , , ) = tokenDistributor
                .allocations(allocIndices[i]);
            if (keccak256(bytes(allocName)) == keccak256(bytes(roundName))) {
                (totalAmount, claimedAmount, , , , , , , ) = tokenDistributor
                    .allocations(allocIndices[i]);
                return (totalAmount, claimedAmount);
            }
        }

        // If not found, return zeros
        return (0, 0);
    }

    /**
     * @dev Helper function to assert token allocation amounts
     * @param user Address of the user
     * @param expectedTokens Expected token amount
     * @param roundName Round name to look for
     */
    function assertTokenAllocation(
        address user,
        uint256 expectedTokens,
        string memory roundName
    ) internal {
        (uint256 totalAmount, uint256 claimedAmount) = getUserTokenAllocation(
            user,
            roundName
        );
        assertEq(
            totalAmount,
            expectedTokens,
            string(
                abi.encodePacked(
                    "Should have correct tokens allocated for ",
                    roundName
                )
            )
        );
        assertEq(claimedAmount, 0, "Should have 0 tokens claimed initially");
    }
}
