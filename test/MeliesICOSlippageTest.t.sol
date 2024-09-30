// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesICO.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

import {MockMelies, MockMeliesICO} from "../src/mock/MockMelies.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

contract MeliesICOSlippageTest is Test {
    MockMeliesICO public meliesICO;
    MockMelies public meliesToken;
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
    uint256 public tgeTimestamp;

    function setUp() public {
        admin = address(this);
        pauser = address(0x1);
        minter = address(0x2);
        burner = address(0x3);
        user1 = address(0x4);
        user2 = address(0x5);

        tgeTimestamp = block.timestamp + 30 days;

        meliesToken = new MockMelies(admin, tgeTimestamp);

        vm.startPrank(admin);
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), pauser);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), minter);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), burner);
        vm.stopPrank();
        usdcToken = new MockERC20("USDC", "USDC");
        usdtToken = new MockERC20("USDT", "USDT");
        uniswapRouter = new MockUniswapV2Router02();
        ethUsdPriceFeed = new MockChainlinkAggregator();

        meliesICO = new MockMeliesICO(
            address(meliesToken),
            address(usdcToken),
            address(usdtToken),
            address(uniswapRouter),
            address(ethUsdPriceFeed),
            tgeTimestamp
        );

        // Set up initial ETH price
        ethUsdPriceFeed.updateAnswer(2000);
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2000);

        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addToWhitelist(1, addresses);

        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
    }

    function test_SetValidSlippageTolerance() public {
        uint256 newSlippageTolerance = 50; // 0.5%
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(newSlippageTolerance);
        assertEq(meliesICO.slippageTolerance(), newSlippageTolerance);
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
        meliesICO.buyWithEth{value: ethAmount}();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertGe(allocation.totalUsdcAmount, minUsdcAmount);
        assertLe(allocation.totalUsdcAmount, expectedUsdcAmount);
    }

    function test_BuyWithEthAtExactSlippageToleranceLimit() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        uint256 expectedUsdcAmount = 2000e6; // 1 ETH = 2000 USDC
        uint256 minUsdcAmount = (expectedUsdcAmount * 995) / 1000; // 0.5% slippage

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1990); // Exactly at the tolerance limit

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertGe(allocation.totalUsdcAmount, minUsdcAmount);
        assertLe(allocation.totalUsdcAmount, expectedUsdcAmount);
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

    function test_SetSlippageToleranceAboveMaximum() public {
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.SlippageToleranceTooHigh.selector);
        meliesICO.updateSlippageTolerance(2000); // 20%
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
        meliesICO.buyWithEth{value: ethAmount}();
    }

    function test_OnlyAdminCanUpdateSlippageTolerance() public {
        vm.prank(user1);
        vm.expectRevert();
        meliesICO.updateSlippageTolerance(50);

        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50);
        assertEq(meliesICO.slippageTolerance(), 50);
    }

    function test_NonAdminCannotUpdateSlippageTolerance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.updateSlippageTolerance(50);
    }

    function test_SetVerySmallSlippageTolerance() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(1); // 0.01%
        assertEq(meliesICO.slippageTolerance(), 1);
    }

    function test_SetSlippageToleranceWithPotentialRoundingIssues() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(33); // 0.33%
        assertEq(meliesICO.slippageTolerance(), 33);
    }

    function test_BuyWithEthPriceMovingDownWithinTolerance() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        uint256 expectedUsdcAmount = 2000e6; // 1 ETH = 2000 USDC
        uint256 minUsdcAmount = (expectedUsdcAmount * 995) / 1000; // 0.5% slippage

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1995); // Slightly lower rate, within tolerance

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertGe(allocation.totalUsdcAmount, minUsdcAmount);
        assertLe(allocation.totalUsdcAmount, expectedUsdcAmount);
    }

    function test_BuyWithEthPriceMovingDownBeyondTolerance() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1989); // Just below the tolerance limit

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        vm.expectRevert("Insufficient output amount");
        meliesICO.buyWithEth{value: ethAmount}();
    }

    function test_MultiplePurchasesWithinSameBlockChangingEthPrices() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        vm.deal(user1, ethAmount * 3);

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2000);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1995);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2005);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertGe(allocation.totalUsdcAmount, 5970e6); // Minimum expected (1990 + 1985 + 1995) * 1e6
        assertLe(allocation.totalUsdcAmount, 6030e6); // Maximum expected (2010 + 2005 + 2015) * 1e6
    }

    function test_PurchasesAcrossDifferentBlocksChangingEthPrices() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 1 ether;
        vm.deal(user1, ethAmount * 3);

        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2000);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        vm.roll(block.number + 1);
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1995);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        vm.roll(block.number + 1);
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2005);
        vm.prank(user1);
        meliesICO.buyWithEth{value: ethAmount}();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertGe(allocation.totalUsdcAmount, 5970e6); // Minimum expected (1990 + 1985 + 1995) * 1e6
        assertLe(allocation.totalUsdcAmount, 6030e6); // Maximum expected (2010 + 2005 + 2015) * 1e6
    }

    function test_SlippageToleranceInteractionWithMinimumPurchase() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 0.05 ether; // Minimum purchase amount (100 USDC)
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 1990); // Just within tolerance

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.BelowMinimumPurchase.selector);
        meliesICO.buyWithEth{value: ethAmount}();
    }

    function test_SlippageToleranceInteractionWithMaximumPurchase() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        uint256 ethAmount = 5 ether; // Maximum purchase amount (10,000 USDC)
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2010); // Just within tolerance

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        vm.expectRevert(IMeliesICO.ExceedsMaximumPurchase.selector);
        meliesICO.buyWithEth{value: ethAmount}();
    }

    function test_SlippageToleranceUpdatedEventEmission() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IMeliesICO.SlippageToleranceUpdated(50);
        meliesICO.updateSlippageTolerance(50);
    }

    function setupSaleRound() internal {
        vm.prank(admin);
        meliesICO.addSaleRound(
            block.timestamp,
            block.timestamp + 7 days,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            30 days,
            180 days,
            10,
            7 days
        );
    }
}
