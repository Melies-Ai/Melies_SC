// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Melies Token Test Suite
/// @notice This contract contains comprehensive tests for the Melies ERC20 token,
/// covering all major functionalities, edge cases, and security aspects.
contract MeliesTest is Test {
    uint256 constant maxSupply = 1000000000; // 1 billion tokens
    Melies public meliesToken;
    address public admin;
    address public pauser;
    address public minter;
    address public burner;
    address public user;
    address public user2;
    address public user3;

    // Custom error selectors
    bytes4 private constant UNAUTHORIZED_SELECTOR = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
    bytes4 private constant ENFORCED_PAUSE_SELECTOR = bytes4(keccak256("EnforcedPause()"));
    bytes32 private constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        admin = address(this);
        pauser = address(0x1);
        minter = address(0x2);
        burner = address(0x3);
        user = address(0x4);
        user2 = address(0x5);
        user3 = address(0x6);

        meliesToken = new Melies(admin, pauser, minter, burner);
    }

    // INITIAL STATE AND SETUP TESTS

    /// @notice Verify the initial state of the contract after deployment
    function test_InitialState() public {
        assertEq(meliesToken.name(), "Melies");
        assertEq(meliesToken.symbol(), "MEL");
        assertEq(meliesToken.totalSupply(), 0);
        assertTrue(meliesToken.hasRole(meliesToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(meliesToken.hasRole(meliesToken.PAUSER_ROLE(), pauser));
        assertTrue(meliesToken.hasRole(meliesToken.MINTER_ROLE(), minter));
        assertTrue(meliesToken.hasRole(meliesToken.BURNER_ROLE(), burner));
    }

    /// @notice Test the token's decimals and initial total supply
    function test_DecimalsAndTotalSupply() public {
        assertEq(meliesToken.decimals(), 18);

        vm.prank(minter);
        meliesToken.mint(user, 1000000);
        assertEq(meliesToken.totalSupply(), 1000000);
    }

    // ROLE MANAGEMENT TESTS

    /// @notice Test granting and revoking roles
    function test_RoleManagement() public {
        address newMinter = address(0x7);
        assertFalse(meliesToken.hasRole(meliesToken.MINTER_ROLE(), newMinter));

        vm.prank(admin);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), newMinter);
        assertTrue(meliesToken.hasRole(meliesToken.MINTER_ROLE(), newMinter));

        vm.prank(admin);
        meliesToken.revokeRole(meliesToken.MINTER_ROLE(), newMinter);
        assertFalse(meliesToken.hasRole(meliesToken.MINTER_ROLE(), newMinter));
    }

    // TOKEN OPERATIONS TESTS

    /// @notice Test minting tokens
    function test_Mint() public {
        assertEq(meliesToken.balanceOf(user), 0);
        assertEq(meliesToken.totalSupply(), 0);
        vm.prank(minter);
        meliesToken.mint(user, 1000);
        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.totalSupply(), 1000);
    }

    /// @notice Test burning tokens
    function test_Burn() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);
        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.totalSupply(), 1000);

        vm.prank(burner);
        meliesToken.burn(user, 500);
        assertEq(meliesToken.balanceOf(user), 500);
        assertEq(meliesToken.totalSupply(), 500);
    }

    /// @notice Test token transfer
    function test_Transfer() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        bool success = meliesToken.transfer(user2, 500);
        assertTrue(success);
        assertEq(meliesToken.balanceOf(user), 500);
        assertEq(meliesToken.balanceOf(user2), 500);
    }

    /// @notice Test approve and transferFrom functionality
    function test_ApproveAndTransferFrom() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        meliesToken.approve(user2, 500);
        assertEq(meliesToken.allowance(user, user2), 500);

        vm.prank(user2);
        bool success = meliesToken.transferFrom(user, user3, 300);
        assertTrue(success);
        assertEq(meliesToken.balanceOf(user), 700);
        assertEq(meliesToken.balanceOf(user3), 300);
        assertEq(meliesToken.allowance(user, user2), 200);
    }

    /// @notice Test event emission on token transfer
    function test_EventEmission() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), user, 1000);
        meliesToken.mint(user, 1000);
    }

    // PAUSING FUNCTIONALITY TESTS

    /// @notice Test pausing the contract
    function test_Pause() public {
        vm.prank(pauser);
        meliesToken.pause();
        assertTrue(meliesToken.paused());
    }

    /// @notice Test unpausing the contract
    function test_Unpause() public {
        vm.startPrank(pauser);
        meliesToken.pause();
        meliesToken.unpause();
        vm.stopPrank();
        assertFalse(meliesToken.paused());
    }

    /// @notice Test transfer while contract is paused
    function test_TransferWhilePaused() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(pauser);
        meliesToken.pause();

        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        vm.prank(user);
        meliesToken.transfer(user2, 500);
    }

    // EDGE CASES AND ERROR HANDLING TESTS

    /// @notice Test unauthorized pause attempt
    function test_PauseUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.PAUSER_ROLE()));
        vm.prank(user);
        meliesToken.pause();
    }

    /// @notice Test unauthorized mint attempt
    function test_MintUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.MINTER_ROLE()));
        vm.prank(user);
        meliesToken.mint(user, 1000);
    }

    /// @notice Test minting exceeding max supply
    function test_MintExceedingMaxSupply() public {
        vm.expectRevert(abi.encodeWithSelector(Melies.ERC20MarketCapExceeded.selector, maxSupply + 1, 0));
        vm.prank(minter);
        meliesToken.mint(user, maxSupply + 1);
    }

    /// @notice Test unauthorized burn attempt
    function test_BurnUnauthorized() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.BURNER_ROLE()));
        vm.prank(user);
        meliesToken.burn(user, 500);
    }

    /// @notice Test zero amount transfer
    function test_ZeroTransfer() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        bool success = meliesToken.transfer(user2, 0);
        assertTrue(success);
        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.balanceOf(user2), 0);
    }

    /// @notice Test transfer to zero address
    function test_TransferToZeroAddress() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        meliesToken.transfer(address(0), 500);
    }

    /// @notice Test minting while contract is paused
    function test_MintWhilePaused() public {
        vm.prank(pauser);
        meliesToken.pause();

        vm.prank(minter);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        meliesToken.mint(user, 1000);

        assertEq(meliesToken.balanceOf(user), 0);
    }

    /// @notice Test burning while contract is paused
    function test_BurnWhilePaused() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(pauser);
        meliesToken.pause();

        vm.prank(burner);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        meliesToken.burn(user, 500);

        assertEq(meliesToken.balanceOf(user), 1000);
    }

    /// @notice Test burning more tokens than available balance
    function test_BurnExceedingBalance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, 1000, 1001));

        meliesToken.burn(user, 1001);

        assertEq(meliesToken.balanceOf(user), 1000);
    }

    /// @notice Test transferring more tokens than available balance
    function test_TransferExceedingBalance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, 1000, 1001));
        meliesToken.transfer(user2, 1001);

        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.balanceOf(user2), 0);
    }

    /// @notice Test approving and decreasing allowance
    function test_ApproveAndDecreaseAllowance() public {
        vm.prank(user);
        meliesToken.approve(user2, 1000);
        assertEq(meliesToken.allowance(user, user2), 1000);

        vm.prank(user);
        meliesToken.approve(user2, 500);
        assertEq(meliesToken.allowance(user, user2), 500);
    }

    /// @notice Test minting approach max supply
    function test_MintApproachingMaxSupply() public {
        uint256 initialMint = maxSupply - 1000; // Mint all but 1000 tokens

        vm.prank(minter);
        meliesToken.mint(user, initialMint);
        assertEq(meliesToken.totalSupply(), initialMint);

        vm.prank(minter);
        meliesToken.mint(user, 999);
        assertEq(meliesToken.totalSupply(), maxSupply - 1);

        vm.prank(minter);
        meliesToken.mint(user, 1);
        assertEq(meliesToken.totalSupply(), maxSupply);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(Melies.ERC20MarketCapExceeded.selector, 1, maxSupply));
        meliesToken.mint(user, 1);
    }

    // EIP-2612 PERMIT FUNCTIONALITY TEST

    /// @notice Test EIP-2612 permit functionality
    function test_Permit() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value);

        // Create the permit message
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute the permit function
        meliesToken.permit(owner, spender, value, deadline, v, r, s);

        // Verify the results
        assertEq(meliesToken.allowance(owner, spender), value);
        assertEq(meliesToken.nonces(owner), 1);
    }
}
