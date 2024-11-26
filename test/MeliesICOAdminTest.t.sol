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

contract MeliesICOAdminTest is Test {
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
            TGE_TIMESTAMP
        );

        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
    }

    function test_AddAndRemoveAdminRole() public {
        address newAdmin = address(0x123);
        vm.prank(admin);
        meliesICO.grantRole(meliesICO.ADMIN_ROLE(), newAdmin);
        assertTrue(meliesICO.hasRole(meliesICO.ADMIN_ROLE(), newAdmin));

        vm.prank(admin);
        meliesICO.revokeRole(meliesICO.ADMIN_ROLE(), newAdmin);
        assertFalse(meliesICO.hasRole(meliesICO.ADMIN_ROLE(), newAdmin));
    }

    function test_AddSaleRoundWithInvalidParameters() public {
        vm.expectRevert(IMeliesICO.InvalidTimeRange.selector);
        vm.prank(admin);
        meliesICO.addSaleRound(
            block.timestamp + 1 days,
            block.timestamp,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            30 days,
            180 days,
            10
        );

        vm.expectRevert(IMeliesICO.InvalidTokenPrice.selector);
        vm.prank(admin);
        meliesICO.addSaleRound(
            block.timestamp,
            block.timestamp + 7 days,
            0,
            1_000_000e6,
            100_000e6,
            100e6,
            10_000e6,
            30 days,
            180 days,
            10
        );

        vm.expectRevert(IMeliesICO.InvalidCap.selector);
        vm.prank(admin);
        meliesICO.addSaleRound(
            block.timestamp,
            block.timestamp + 7 days,
            0.1e6,
            100_000e6,
            1_000_000e6,
            100e6,
            10_000e6,
            30 days,
            180 days,
            10
        );
    }

    function test_AddFiatPurchase() public {
        setupSaleRound();
        vm.startPrank(admin);
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addFiatPurchase(user1, 1000e6);
        vm.stopPrank();
        IMeliesICO.Allocation memory allocation = meliesICO
            .getAllocationDetails(user1, 0);
        assertEq(allocation.totalUsdcAmount, 1000e6);
    }

    function test_EndIcoWithAllRoundsReachingSoftCap() public {
        vm.startPrank(admin);
        meliesICO.addSaleRound(
            block.timestamp,
            block.timestamp + 7 days,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            100_000e6,
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
            200_000e6,
            60 days,
            360 days,
            5
        );

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addToWhitelist(1, addresses);
        meliesICO.addFiatPurchase(user1, 100_000e6);
        vm.warp(block.timestamp + 7 days);
        meliesICO.addFiatPurchase(user1, 200_000e6);
        meliesICO.endIco();
        vm.stopPrank();
        assertTrue(meliesICO.icoEnded());
        assertTrue(meliesICO.claimEnabled());
    }

    function test_EndIcoWithSomeRoundsNotReachingSoftCap() public {
        vm.startPrank(admin);
        meliesICO.addSaleRound(
            block.timestamp,
            block.timestamp + 7 days,
            0.1e6,
            1_000_000e6,
            100_000e6,
            100e6,
            100_000e6,
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
            200_000e6,
            60 days,
            360 days,
            5
        );

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addToWhitelist(1, addresses);
        meliesICO.addFiatPurchase(user1, 100_000e6);
        vm.warp(block.timestamp + 7 days);
        meliesICO.addFiatPurchase(user1, 100_000e6);
        meliesICO.endIco();
        vm.stopPrank();
        assertTrue(meliesICO.icoEnded());
        assertFalse(meliesICO.claimEnabled());
    }

    function test_EndIcoTwice() public {
        setupSaleRound();
        vm.startPrank(admin);
        meliesICO.endIco();
        vm.expectRevert(IMeliesICO.IcoAlreadyEnded.selector);
        meliesICO.endIco();
        vm.stopPrank();
    }

    function test_OnlyAdminCanAddSaleRound() public {
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
            10
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
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
    }

    function test_OnlyAdminCanUpdateSlippageTolerance() public {
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(50); // 0.5%

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.updateSlippageTolerance(100);
    }

    function test_OnlyAdminCanAddFiatPurchase() public {
        setupSaleRound();

        vm.startPrank(admin);
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        meliesICO.addToWhitelist(0, addresses);
        meliesICO.addFiatPurchase(user1, 1000e6);
        vm.stopPrank();

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

    function test_OnlyAdminCanWithdrawUsdc() public {
        setupSaleRoundAndPurchase();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        meliesICO.withdrawUsdc();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.withdrawUsdc();
    }

    function test_OnlyAdminCanWithdrawUsdt() public {
        setupSaleRoundAndPurchase();

        vm.prank(admin);
        meliesICO.endIco();

        vm.prank(admin);
        meliesICO.withdrawUsdt();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.withdrawUsdc();
    }

    function test_OnlyAdminCanWithdrawEth() public {
        setupSaleRoundAndPurchase();

        // Set up Uniswap mock for ETH to USDC conversion
        ethUsdPriceFeed.updateAnswer(2000);
        uniswapRouter.setExchangeRate(address(0), address(usdcToken), 2000);

        // User buys tokens with 1 ETH
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        meliesICO.buyWithEth{value: 1 ether}();

        vm.prank(admin);
        meliesICO.endIco();

        // All ETH are swapped for USDC
        vm.expectRevert(IMeliesICO.NoEthToWithdraw.selector);
        vm.prank(admin);
        meliesICO.withdrawEth();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.withdrawEth();
    }

    function test_WithdrawEthBeforeIcoEnds() public {
        setupSaleRound();
        vm.deal(address(meliesICO), 1 ether);
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.IcoNotEndedYet.selector);
        meliesICO.withdrawEth();
    }

    function test_WithdrawEthWithNoBalance() public {
        setupSaleRound();
        vm.prank(admin);
        meliesICO.endIco();

        uint256 initialBalance = address(admin).balance;

        vm.expectRevert(IMeliesICO.NoEthToWithdraw.selector);
        vm.prank(admin);
        meliesICO.withdrawEth();
        assertEq(admin.balance, initialBalance);
    }

    function test_OnlyAdminCanEndIco() public {
        setupSaleRoundAndPurchase();

        vm.prank(admin);
        meliesICO.endIco();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.endIco();
    }

    function test_OnlyAdminCanWithdrawRoundFunds() public {
        setupSaleRound();
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        vm.startPrank(user1);
        usdcToken.mint(user1, 50_000e6);
        usdcToken.approve(address(meliesICO), 50_000e6);
        usdtToken.mint(user1, 50_000e6);
        usdtToken.approve(address(meliesICO), 50_000e6);
        meliesICO.buyWithUsdc(10_000e6);
        meliesICO.buyWithUsdc(10_000e6);
        meliesICO.buyWithUsdc(10_000e6);
        meliesICO.buyWithUsdc(10_000e6);
        meliesICO.buyWithUsdc(10_000e6);
        meliesICO.buyWithUsdt(10_000e6);
        meliesICO.buyWithUsdt(10_000e6);
        meliesICO.buyWithUsdt(10_000e6);
        meliesICO.buyWithUsdt(10_000e6);
        meliesICO.buyWithUsdt(10_000e6);
        vm.stopPrank();

        vm.prank(admin);
        meliesICO.endIco();

        uint256 initialUsdcBalance = usdcToken.balanceOf(admin);
        uint256 initialUsdtBalance = usdtToken.balanceOf(admin);
        vm.prank(admin);
        meliesICO.withdrawRoundFunds(0);
        assertEq(usdcToken.balanceOf(admin) - initialUsdcBalance, 50_000e6);
        assertEq(usdtToken.balanceOf(admin) - initialUsdtBalance, 50_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.withdrawRoundFunds(0);
    }

    function test_AdminCannotSetInvalidSlippageTolerance() public {
        vm.expectRevert(IMeliesICO.SlippageToleranceTooHigh.selector);
        vm.prank(admin);
        meliesICO.updateSlippageTolerance(10001); // 100.01%
    }

    function test_AdminCanRecoverAccidentallySentTokens() public {
        MockERC20 accidentalToken = new MockERC20("Accidental", "ACC");
        accidentalToken.mint(address(meliesICO), 1000e18);
        uint256 initialBalance = accidentalToken.balanceOf(admin);
        vm.prank(admin);
        meliesICO.recoverTokens(address(accidentalToken), 1000e18);
        assertEq(accidentalToken.balanceOf(admin) - initialBalance, 1000e18);
    }

    function test_AdminCannotRecoverCoreTokens() public {
        setupSaleRound();
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.CannotRecoverMeliesTokens.selector);
        meliesICO.recoverTokens(address(meliesToken), 1000e6);
    }

    function test_AdminCannotRecoverUSDCTokens() public {
        setupSaleRound();
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.CannotRecoverUsdcTokens.selector);
        meliesICO.recoverTokens(address(usdcToken), 1000e6);
    }

    function test_AdminCannotRecoverUSDTTokens() public {
        setupSaleRound();
        vm.prank(admin);
        vm.expectRevert(IMeliesICO.CannotRecoverUsdtTokens.selector);
        meliesICO.recoverTokens(address(usdtToken), 1000e6);
    }

    function test_OnlyAdminCanAdjustCliffAndVesting() public {
        setupSaleRound();

        vm.prank(admin);
        meliesICO.adjustCliffAndVesting(0, 60 days, 240 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                meliesICO.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        meliesICO.adjustCliffAndVesting(0, 90 days, 300 days);
    }

    // Helper functions

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
            10
        );
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

    function setupSaleRoundAndPurchase() internal {
        setupSaleRound();
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        vm.prank(admin);
        meliesICO.addToWhitelist(0, addresses);

        usdcToken.mint(user1, 1000e6);
        vm.prank(user1);
        usdcToken.approve(address(meliesICO), 1000e6);
        vm.prank(user1);
        meliesICO.buyWithUsdc(1000e6);

        usdtToken.mint(user2, 1000e6);
        vm.prank(user2);
        usdtToken.approve(address(meliesICO), 1000e6);
        vm.prank(user2);
        meliesICO.buyWithUsdt(1000e6);
    }
}
