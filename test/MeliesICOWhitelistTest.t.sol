// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MeliesICO.sol";
import "../src/Melies.sol";
import "../src/MeliesTokenDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockMeliesICO} from "../src/mock/MockMelies.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {MockUniswapV2Router02} from "../src/mock/MockUniswapV2Router02.sol";
import {MockChainlinkAggregator} from "../src/mock/MockChainlinkAggregator.sol";

contract MeliesICOWhitelistTest is Test {
    MockMeliesICO public meliesICO;
    MeliesTokenDistributor public tokenDistributor;
    Melies public meliesToken;
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
        meliesToken = new Melies(admin);

        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), admin);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), admin);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), admin);
        usdcToken = new MockERC20("USDC", "USDC");
        usdtToken = new MockERC20("USDT", "USDT");
        uniswapRouter = new MockUniswapV2Router02();
        ethUsdPriceFeed = new MockChainlinkAggregator();

        // Deploy TokenDistributor first
        tokenDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            block.timestamp + 1 days,
            admin,
            address(0x111), // Community
            address(0x222), // Treasury
            address(0x333), // Partners
            address(0x444), // Team
            address(0x555), // Liquidity
            address(0x666) // AI Systems
        );

        meliesICO = new MockMeliesICO(
            address(meliesToken),
            address(tokenDistributor),
            address(usdcToken),
            address(usdtToken),
            address(uniswapRouter),
            address(ethUsdPriceFeed),
            block.timestamp + 1 days
        );

        // Grant roles
        meliesToken.grantRole(
            meliesToken.MINTER_ROLE(),
            address(tokenDistributor)
        );
        tokenDistributor.grantRole(
            tokenDistributor.ICO_ROLE(),
            address(meliesICO)
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

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 1000e6); // 1000 USDC

        // Check user's token allocation in TokenDistributor
        uint256[] memory allocIndices = tokenDistributor
            .getAllocationsForBeneficiary(user1);
        assertEq(allocIndices.length, 1, "Should have one allocation");
        (uint256 totalAmount, , , , , , , , ) = tokenDistributor.allocations(
            allocIndices[0]
        );
        assertEq(totalAmount, 10_000e8, "Should have 10,000 tokens allocated");
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

        // Check USD allocations in ICO
        IMeliesICO.Allocation memory allocation1 = meliesICO
            .getAllocationDetails(user1, 0);
        IMeliesICO.Allocation memory allocation2 = meliesICO
            .getAllocationDetails(user2, 1);
        assertEq(allocation1.totalUsdcAmount, 1000e6);
        assertEq(allocation2.totalUsdcAmount, 1000e6);

        // Check token allocations in TokenDistributor
        uint256[] memory allocIndices1 = tokenDistributor
            .getAllocationsForBeneficiary(user1);
        uint256[] memory allocIndices2 = tokenDistributor
            .getAllocationsForBeneficiary(user2);
        (uint256 totalAmount1, , , , , , , , ) = tokenDistributor.allocations(
            allocIndices1[0]
        );
        (uint256 totalAmount2, , , , , , , , ) = tokenDistributor.allocations(
            allocIndices2[0]
        );
        assertEq(totalAmount1, 10000e8); // Round 0: 1000 USDC / 0.1 = 10000 tokens
        assertEq(totalAmount2, 5000e8); // Round 1: 1000 USDC / 0.2 = 5000 tokens
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

        // Check that user has token allocation in TokenDistributor
        uint256[] memory allocIndices = tokenDistributor
            .getAllocationsForBeneficiary(user1);
        assertEq(allocIndices.length, 1, "Should have one allocation");
        (uint256 totalAmount, , , , , , , , ) = tokenDistributor.allocations(
            allocIndices[0]
        );
        assertGt(totalAmount, 0, "Should have tokens allocated");
    }

    function test_WhitelistWithFiatPurchase() public {
        setupSaleRound();
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addFiatPurchase(user1, 1000e6);
        vm.stopPrank();

        // Check user's allocation in ICO (USD tracking for refunds)
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 1000e6); // 1000 USD (fiat treated as USDC equivalent)

        // Check user's token allocation in TokenDistributor
        uint256[] memory allocIndices = tokenDistributor
            .getAllocationsForBeneficiary(user1);
        assertEq(allocIndices.length, 1, "Should have one allocation");
        (uint256 totalAmount, , , , , , , , ) = tokenDistributor.allocations(
            allocIndices[0]
        );
        assertEq(totalAmount, 10000e8, "Should have 10,000 tokens allocated");
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
            10
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
            10
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
            5
        );
        vm.stopPrank();
    }
}
