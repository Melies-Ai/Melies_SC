// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesICO.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockMelies, MockMeliesICO} from "../src/mock/MockMelies.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

contract MeliesICOWhitelistTest is Test {
    MockMeliesICO public meliesICO;
    MockMelies public meliesToken;
    MockERC20 public usdcToken;
    MockERC20 public usdtToken;
    MockUniswapV2Router02 public uniswapRouter;
    MockChainlinkAggregator public ethUsdPriceFeed;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);

    uint256 public constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 public constant INITIAL_ETH_PRICE = 2000; // 1 ETH = 2000 USDC

    function setUp() public {
        vm.startPrank(admin);

        // Deploy necessary contracts
        meliesToken = new MockMelies(admin, block.timestamp + 1 days);

        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), admin);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), admin);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), admin);
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
            block.timestamp + 1 days
        );

        // Set up initial ETH price
        ethUsdPriceFeed.updateAnswer(int256(INITIAL_ETH_PRICE));
        uniswapRouter.setExchangeRate(
            address(0),
            address(usdcToken),
            INITIAL_ETH_PRICE
        );

        // Set up initial balances
        usdcToken.mint(user1, INITIAL_BALANCE);
        usdcToken.mint(user2, INITIAL_BALANCE);
        usdcToken.mint(user3, INITIAL_BALANCE);

        vm.stopPrank();
    }

    function test_AddToWhitelist() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        meliesICO.addToWhitelist(0, addresses);

        assertTrue(meliesICO.whitelist(0, user1));
        assertTrue(meliesICO.whitelist(0, user2));
        assertFalse(meliesICO.whitelist(0, user3));
        vm.stopPrank();
    }

    function test_RemoveFromWhitelist() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;

        meliesICO.addToWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);

        assertFalse(meliesICO.whitelist(0, user1));
        assertFalse(meliesICO.whitelist(0, user2));
        vm.stopPrank();
    }

    function test_BuyTokensWhenWhitelisted() public {
        setupSaleRound();
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        vm.stopPrank();

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalTokenAmount, 10_000e8);
    }

    function test_BuyTokensWhenNotWhitelisted() public {
        setupSaleRound();

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.expectRevert(IMeliesICO.NotWhitelisted.selector);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();
    }

    function test_BuyTokensAfterRemovalFromWhitelist() public {
        setupSaleRound();
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);
        vm.stopPrank();

        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.expectRevert(IMeliesICO.NotWhitelisted.selector);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();
    }

    function test_MultipleRoundsWhitelist() public {
        setupMultipleSaleRounds();
        vm.startPrank(admin);
        address[] memory addresses1 = new address[](1);
        addresses1[0] = user1;
        meliesICO.addToWhitelist(0, addresses1);

        address[] memory addresses2 = new address[](1);
        addresses2[0] = user2;
        meliesICO.addToWhitelist(1, addresses2);
        vm.stopPrank();

        assertTrue(meliesICO.whitelist(0, user1));
        assertFalse(meliesICO.whitelist(0, user2));
        assertFalse(meliesICO.whitelist(1, user1));
        assertTrue(meliesICO.whitelist(1, user2));

        // Test buying in different rounds
        vm.warp(block.timestamp + 1);
        vm.startPrank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days + 1);
        vm.startPrank(user2);
        usdcToken.approve(address(meliesICO), 1000e6);
        meliesICO.buyWithUsdc(1000e6);
        vm.stopPrank();

        IMeliesICO.Allocation memory allocation1 = meliesICO
            .getAllocationDetails(user1, 0);
        IMeliesICO.Allocation memory allocation2 = meliesICO
            .getAllocationDetails(user2, 1);
        assertEq(allocation1.totalTokenAmount, 10000e8);
        assertEq(allocation2.totalTokenAmount, 5000e8);
    }

    function test_OnlyAdminCanAddToWhitelist() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        vm.prank(user2);
        vm.expectRevert();
        meliesICO.addToWhitelist(0, addresses);
    }

    function test_OnlyAdminCanRemoveFromWhitelist() public {
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        vm.prank(user2);
        vm.expectRevert();
        meliesICO.removeFromWhitelist(0, addresses);
    }

    function test_AddAlreadyWhitelistedAddress() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addToWhitelist(0, addresses);

        assertTrue(meliesICO.whitelist(0, user1));
        vm.stopPrank();
    }

    function test_RemoveNonWhitelistedAddress() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;

        meliesICO.removeFromWhitelist(0, addresses);

        assertFalse(meliesICO.whitelist(0, user1));
        vm.stopPrank();
    }

    function test_WhitelistWithEmptyAddressList() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](0);

        meliesICO.addToWhitelist(0, addresses);
        meliesICO.removeFromWhitelist(0, addresses);
        vm.stopPrank();
    }

    function test_WhitelistWithEthPurchase() public {
        setupSaleRound();
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        vm.stopPrank();

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertGt(allocation.totalTokenAmount, 0);
    }

    function test_WhitelistWithFiatPurchase() public {
        setupSaleRound();
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addFiatPurchase(user1, 1000e6);
        vm.stopPrank();

        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalTokenAmount, 10000e8);
    }

    function test_GasUsageForAddingToWhitelist() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](100);
        for (uint i = 0; i < 100; i++) {
            addresses[i] = address(uint160(i + 1000));
        }

        uint256 gasStart = gasleft();
        meliesICO.addToWhitelist(0, addresses);
        uint256 gasUsed = gasStart - gasleft();

        assertLt(gasUsed, 3000000);
        vm.stopPrank();
    }

    function test_GasUsageForRemovingFromWhitelist() public {
        vm.startPrank(admin);
        address[] memory addresses = new address[](100);
        for (uint i = 0; i < 100; i++) {
            addresses[i] = address(uint160(i + 1000));
        }
        meliesICO.addToWhitelist(0, addresses);

        uint256 gasStart = gasleft();
        meliesICO.removeFromWhitelist(0, addresses);
        uint256 gasUsed = gasStart - gasleft();

        assertLt(gasUsed, 3000000);
        vm.stopPrank();
    }

    // Helper functions

    function setupSaleRound() internal {
        vm.startPrank(admin);
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
        vm.stopPrank();
    }

    function setupMultipleSaleRounds() internal {
        vm.startPrank(admin);
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
        meliesICO.addSaleRound(
            block.timestamp + 7 days,
            block.timestamp + 14 days,
            0.2e6,
            2_000_000e6,
            200_000e6,
            200e6,
            20_000e6,
            60 days,
            360 days,
            5,
            14 days
        );
        vm.stopPrank();
    }
}
