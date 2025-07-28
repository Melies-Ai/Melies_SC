// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Melies.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Melies Token Test Suite
/// @author Melies Team
/// @notice Comprehensive test suite for the Melies ERC20 token contract
/// @dev Tests all major functionalities, edge cases, and security aspects
contract MeliesTest is Test {
    // =============================================================================
    // CONSTANTS
    // =============================================================================

    uint256 constant MAX_SUPPLY = 1_000_000_000e8; // 1 billion tokens with 8 decimals

    // Custom error selectors for testing
    bytes4 private constant UNAUTHORIZED_SELECTOR =
        bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
    bytes4 private constant ENFORCED_PAUSE_SELECTOR = bytes4(keccak256("EnforcedPause()"));
    bytes4 private constant INSUFFICIENT_BALANCE_SELECTOR =
        bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)"));
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    Melies public meliesToken;

    // Test addresses
    address public admin;
    address public pauser;
    address public minter;
    address public burner;
    address public user;
    address public user2;
    address public user3;

    // =============================================================================
    // SETUP
    // =============================================================================

    function setUp() public {
        admin = address(this);
        pauser = address(0x1);
        minter = address(0x2);
        burner = address(0x3);
        user = address(0x4);
        user2 = address(0x5);
        user3 = address(0x6);

        meliesToken = new Melies(admin);

        vm.startPrank(admin);
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), pauser);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), minter);
        meliesToken.grantRole(meliesToken.BURNER_ROLE(), burner);
        vm.stopPrank();
    }

    // =============================================================================
    // CONTRACT INITIALIZATION TESTS
    // =============================================================================

    function test_InitialState() public {
        assertEq(meliesToken.name(), "Melies");
        assertEq(meliesToken.symbol(), "MEL");
        assertEq(meliesToken.decimals(), 8);
        assertEq(meliesToken.totalSupply(), 0);
        assertEq(meliesToken.maxTotalSupply(), MAX_SUPPLY);
        assertFalse(meliesToken.paused());
    }

    function test_RoleInitialization() public {
        assertTrue(meliesToken.hasRole(meliesToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(meliesToken.hasRole(meliesToken.PAUSER_ROLE(), pauser));
        assertTrue(meliesToken.hasRole(meliesToken.MINTER_ROLE(), minter));
        assertTrue(meliesToken.hasRole(meliesToken.BURNER_ROLE(), burner));
    }

    function test_RoleGetters() public {
        assertEq(meliesToken.DEFAULT_ADMIN_ROLE(), 0x00);
        assertEq(meliesToken.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(meliesToken.MINTER_ROLE(), keccak256("MINTER_ROLE"));
        assertEq(meliesToken.BURNER_ROLE(), keccak256("BURNER_ROLE"));
    }

    // =============================================================================
    // ROLE MANAGEMENT TESTS
    // =============================================================================

    function test_RoleGrantingAndRevoking() public {
        bytes32 role = meliesToken.MINTER_ROLE();
        address newMinter = address(0x7);

        // Grant role
        vm.prank(admin);
        meliesToken.grantRole(role, newMinter);
        assertTrue(meliesToken.hasRole(role, newMinter));

        // Revoke role
        vm.prank(admin);
        meliesToken.revokeRole(role, newMinter);
        assertFalse(meliesToken.hasRole(role, newMinter));
    }

    function test_RoleRenouncing() public {
        bytes32 role = meliesToken.MINTER_ROLE();
        address newMinter = address(0x7);
        vm.prank(admin);
        meliesToken.grantRole(role, newMinter);

        vm.prank(newMinter);
        meliesToken.renounceRole(role, newMinter);
        assertFalse(meliesToken.hasRole(role, newMinter));
    }

    function test_UnauthorizedRoleManagement() public {
        bytes32 role = meliesToken.MINTER_ROLE();
        address newMinter = address(0x7);

        vm.expectRevert();
        vm.prank(user);
        meliesToken.grantRole(role, newMinter);

        vm.expectRevert();
        vm.prank(user);
        meliesToken.revokeRole(role, newMinter);
    }

    function test_AdminRoleManagement() public {
        address newAdmin = address(0x7);

        // Grant admin role
        vm.prank(admin);
        meliesToken.grantRole(meliesToken.DEFAULT_ADMIN_ROLE(), newAdmin);
        assertTrue(meliesToken.hasRole(meliesToken.DEFAULT_ADMIN_ROLE(), newAdmin));

        // New admin can revoke original admin
        vm.prank(newAdmin);
        meliesToken.revokeRole(meliesToken.DEFAULT_ADMIN_ROLE(), admin);
        assertFalse(meliesToken.hasRole(meliesToken.DEFAULT_ADMIN_ROLE(), admin));
    }

    // =============================================================================
    // MINTING TESTS
    // =============================================================================

    function test_BasicMinting() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.totalSupply(), 1000);
    }

    function test_MintToZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        meliesToken.mint(address(0), 1000);
    }

    function test_MintZeroAmount() public {
        vm.prank(minter);
        meliesToken.mint(user, 0);

        assertEq(meliesToken.balanceOf(user), 0);
        assertEq(meliesToken.totalSupply(), 0);
    }

    function test_MintUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.MINTER_ROLE()));
        vm.prank(user);
        meliesToken.mint(user, 1000);
    }

    function test_MintExceedingMaxSupply() public {
        vm.expectRevert(abi.encodeWithSelector(Melies.ERC20MarketCapExceeded.selector, MAX_SUPPLY + 1, 0));
        vm.prank(minter);
        meliesToken.mint(user, MAX_SUPPLY + 1);
    }

    function test_MintAtMaxSupplyBoundary() public {
        // Mint all but 1 token
        vm.prank(minter);
        meliesToken.mint(user, MAX_SUPPLY - 1);

        // Mint the last token
        vm.prank(minter);
        meliesToken.mint(user2, 1);

        assertEq(meliesToken.totalSupply(), MAX_SUPPLY);
        assertEq(meliesToken.balanceOf(user), MAX_SUPPLY - 1);
        assertEq(meliesToken.balanceOf(user2), 1);
    }

    function test_MintWithPrecision() public {
        uint256 smallAmount = 1; // 0.00000001 tokens
        uint256 mediumAmount = 1_000_000; // 0.01 tokens
        uint256 largeAmount = 100_000_000; // 1 token

        vm.startPrank(minter);
        meliesToken.mint(user, smallAmount);
        meliesToken.mint(user2, mediumAmount);
        meliesToken.mint(user3, largeAmount);
        vm.stopPrank();

        assertEq(meliesToken.balanceOf(user), smallAmount);
        assertEq(meliesToken.balanceOf(user2), mediumAmount);
        assertEq(meliesToken.balanceOf(user3), largeAmount);
        assertEq(meliesToken.totalSupply(), smallAmount + mediumAmount + largeAmount);
    }

    // =============================================================================
    // BURNING TESTS
    // =============================================================================

    function test_BasicBurning() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(burner);
        meliesToken.burn(user, 500);

        assertEq(meliesToken.balanceOf(user), 500);
        assertEq(meliesToken.totalSupply(), 500);
    }

    function test_BurnFromZeroAddress() public {
        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        meliesToken.burn(address(0), 500);
    }

    function test_BurnZeroAmount() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(burner);
        meliesToken.burn(user, 0);

        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.totalSupply(), 1000);
    }

    function test_BurnUnauthorized() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.BURNER_ROLE()));
        vm.prank(user);
        meliesToken.burn(user, 500);
    }

    function test_BurnExceedingBalance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(INSUFFICIENT_BALANCE_SELECTOR, user, 1000, 1001));
        meliesToken.burn(user, 1001);
    }

    function test_BurnEntireBalance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(burner);
        meliesToken.burn(user, 1000);

        assertEq(meliesToken.balanceOf(user), 0);
        assertEq(meliesToken.totalSupply(), 0);
    }

    // =============================================================================
    // TRANSFER TESTS
    // =============================================================================

    function test_BasicTransfer() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        bool success = meliesToken.transfer(user2, 500);

        assertTrue(success);
        assertEq(meliesToken.balanceOf(user), 500);
        assertEq(meliesToken.balanceOf(user2), 500);
    }

    function test_TransferToSelf() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        bool success = meliesToken.transfer(user, 500);

        assertTrue(success);
        assertEq(meliesToken.balanceOf(user), 1000); // Balance unchanged
    }

    function test_TransferZeroAmount() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        bool success = meliesToken.transfer(user2, 0);

        assertTrue(success);
        assertEq(meliesToken.balanceOf(user), 1000);
        assertEq(meliesToken.balanceOf(user2), 0);
    }

    function test_TransferToZeroAddress() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        meliesToken.transfer(address(0), 500);
    }

    function test_TransferExceedingBalance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(INSUFFICIENT_BALANCE_SELECTOR, user, 1000, 1001));
        meliesToken.transfer(user2, 1001);
    }

    function test_TransferWithExactBalance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        meliesToken.transfer(user2, 1000);

        assertEq(meliesToken.balanceOf(user), 0);
        assertEq(meliesToken.balanceOf(user2), 1000);
    }

    // =============================================================================
    // APPROVAL AND TRANSFERFROM TESTS
    // =============================================================================

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

    function test_ApproveZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        meliesToken.approve(address(0), 100);
    }

    function test_ApproveWithSameAmount() public {
        vm.prank(user);
        meliesToken.approve(user2, 1000);
        assertEq(meliesToken.allowance(user, user2), 1000);

        vm.prank(user);
        meliesToken.approve(user2, 1000); // Same amount
        assertEq(meliesToken.allowance(user, user2), 1000);
    }

    function test_ApproveAndDecreaseAllowance() public {
        vm.prank(user);
        meliesToken.approve(user2, 1000);
        assertEq(meliesToken.allowance(user, user2), 1000);

        vm.prank(user);
        meliesToken.approve(user2, 500);
        assertEq(meliesToken.allowance(user, user2), 500);
    }

    function test_TransferFromInsufficientAllowance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        meliesToken.approve(user2, 500);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, user2, 500, 501));
        meliesToken.transferFrom(user, user3, 501);
    }

    function test_TransferFromZeroAllowance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, user2, 0, 100));
        meliesToken.transferFrom(user, user3, 100);
    }

    function test_TransferFromWithExactAllowance() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(user);
        meliesToken.approve(user2, 500);

        vm.prank(user2);
        meliesToken.transferFrom(user, user3, 500);

        assertEq(meliesToken.balanceOf(user), 500);
        assertEq(meliesToken.balanceOf(user3), 500);
        assertEq(meliesToken.allowance(user, user2), 0);
    }

    // =============================================================================
    // PAUSE FUNCTIONALITY TESTS
    // =============================================================================

    function test_PauseAndUnpause() public {
        vm.prank(pauser);
        meliesToken.pause();
        assertTrue(meliesToken.paused());

        vm.prank(pauser);
        meliesToken.unpause();
        assertFalse(meliesToken.paused());
    }

    function test_PauseUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.PAUSER_ROLE()));
        vm.prank(user);
        meliesToken.pause();
    }

    function test_UnpauseUnauthorized() public {
        vm.prank(pauser);
        meliesToken.pause();

        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.PAUSER_ROLE()));
        vm.prank(user);
        meliesToken.unpause();
    }

    function test_PauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        meliesToken.pause();
        assertTrue(meliesToken.paused());

        vm.prank(pauser);
        vm.expectRevert();
        meliesToken.pause();
    }

    function test_UnpauseWhenNotPaused() public {
        assertFalse(meliesToken.paused());

        vm.prank(pauser);
        vm.expectRevert();
        meliesToken.unpause();
    }

    function test_TransferWhilePaused() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(pauser);
        meliesToken.pause();

        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        vm.prank(user);
        meliesToken.transfer(user2, 500);
    }

    function test_MintWhilePaused() public {
        vm.prank(pauser);
        meliesToken.pause();

        vm.prank(minter);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        meliesToken.mint(user, 1000);
    }

    function test_BurnWhilePaused() public {
        vm.prank(minter);
        meliesToken.mint(user, 1000);

        vm.prank(pauser);
        meliesToken.pause();

        vm.prank(burner);
        vm.expectRevert(ENFORCED_PAUSE_SELECTOR);
        meliesToken.burn(user, 500);
    }

    function test_ApproveWhilePaused() public {
        vm.prank(pauser);
        meliesToken.pause();

        // Approve should still work when paused
        vm.prank(user);
        meliesToken.approve(user2, 500);
        assertEq(meliesToken.allowance(user, user2), 500);
    }

    // =============================================================================
    // PERMIT FUNCTIONALITY TESTS
    // =============================================================================

    function test_BasicPermit() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        meliesToken.permit(owner, spender, value, deadline, v, r, s);

        assertEq(meliesToken.allowance(owner, spender), value);
        assertEq(meliesToken.nonces(owner), 1);
    }

    function test_PermitExpiredDeadline() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 1000;
        uint256 deadline = block.timestamp - 1; // Expired

        vm.prank(minter);
        meliesToken.mint(owner, value);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        vm.expectRevert();
        meliesToken.permit(owner, spender, value, deadline, v, r, s);
    }

    function test_PermitInvalidSignature() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        s = bytes32(uint256(s) ^ 1); // Modify signature to make it invalid

        vm.expectRevert();
        meliesToken.permit(owner, spender, value, deadline, v, r, s);
    }

    function test_PermitZeroAddressSpender() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0), value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        meliesToken.permit(owner, address(0), value, deadline, v, r, s);
    }

    function test_PermitReusedNonce() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        meliesToken.permit(owner, spender, value, deadline, v, r, s);

        vm.expectRevert();
        meliesToken.permit(owner, spender, value, deadline, v, r, s);
    }

    function test_PermitZeroValue() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 0;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, 1000);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        meliesToken.permit(owner, spender, value, deadline, v, r, s);

        assertEq(meliesToken.allowance(owner, spender), 0);
        assertEq(meliesToken.nonces(owner), 1);
    }

    function test_MultiplePermits() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender1 = user2;
        address spender2 = user3;
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value * 2);

        // First permit
        bytes32 digest1 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender1,
                        value,
                        0, // nonce 0
                        deadline
                    )
                )
            )
        );

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(privateKey, digest1);
        meliesToken.permit(owner, spender1, value, deadline, v1, r1, s1);
        assertEq(meliesToken.nonces(owner), 1);

        // Second permit
        bytes32 digest2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender2,
                        value,
                        1, // nonce 1
                        deadline
                    )
                )
            )
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(privateKey, digest2);
        meliesToken.permit(owner, spender2, value, deadline, v2, r2, s2);
        assertEq(meliesToken.nonces(owner), 2);
    }

    function test_DomainSeparator() public {
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Melies")),
                keccak256(bytes("1")),
                block.chainid,
                address(meliesToken)
            )
        );

        assertEq(meliesToken.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    // =============================================================================
    // EVENT EMISSION TESTS
    // =============================================================================

    function test_TransferEventEmission() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), user, 1000);
        meliesToken.mint(user, 1000);
    }

    function test_ApprovalEventEmission() public {
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(user, user2, 500);
        meliesToken.approve(user2, 500);
    }

    // =============================================================================
    // INTEGRATION TESTS
    // =============================================================================

    function test_MultipleOperations() public {
        vm.startPrank(minter);
        meliesToken.mint(user, 1000);
        meliesToken.mint(user2, 2000);
        meliesToken.mint(user3, 3000);
        vm.stopPrank();

        vm.startPrank(user);
        meliesToken.approve(user2, 500);
        meliesToken.transfer(user3, 200);
        vm.stopPrank();

        vm.startPrank(user2);
        meliesToken.transferFrom(user, user3, 300);
        vm.stopPrank();

        assertEq(meliesToken.balanceOf(user), 500);
        assertEq(meliesToken.balanceOf(user2), 2000);
        assertEq(meliesToken.balanceOf(user3), 3500);
        assertEq(meliesToken.allowance(user, user2), 200);
    }

    function test_PermitAndPauseIntegration() public {
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(minter);
        meliesToken.mint(owner, value);

        // Pause the contract
        vm.prank(pauser);
        meliesToken.pause();

        // Permit should still work when paused
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                meliesToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, meliesToken.nonces(owner), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        meliesToken.permit(owner, spender, value, deadline, v, r, s);

        assertEq(meliesToken.allowance(owner, spender), value);
        assertEq(meliesToken.nonces(owner), 1);
    }

    // =============================================================================
    // EDGE CASES AND BOUNDARY TESTS
    // =============================================================================

    function test_MaxSupplyBoundaryConditions() public {
        Melies meliesTokenA = new Melies(admin);

        vm.startPrank(admin);
        meliesTokenA.grantRole(meliesTokenA.PAUSER_ROLE(), pauser);
        meliesTokenA.grantRole(meliesTokenA.MINTER_ROLE(), minter);
        meliesTokenA.grantRole(meliesTokenA.BURNER_ROLE(), burner);
        vm.stopPrank();
        // Test minting exactly to max supply
        vm.prank(minter);
        meliesTokenA.mint(user, MAX_SUPPLY);
        assertEq(meliesTokenA.totalSupply(), MAX_SUPPLY);

        // Test minting one token below max supply
        Melies meliesTokenB = new Melies(admin);

        vm.startPrank(admin);
        meliesTokenB.grantRole(meliesTokenB.PAUSER_ROLE(), pauser);
        meliesTokenB.grantRole(meliesTokenB.MINTER_ROLE(), minter);
        meliesTokenB.grantRole(meliesTokenB.BURNER_ROLE(), burner);
        vm.stopPrank();

        vm.prank(minter);
        meliesTokenB.mint(user2, MAX_SUPPLY - 1);
        assertEq(meliesTokenB.totalSupply(), MAX_SUPPLY - 1);

        // Test minting with amounts that sum to max supply exactly
        Melies meliesTokenC = new Melies(admin);

        vm.startPrank(admin);
        meliesTokenC.grantRole(meliesTokenC.PAUSER_ROLE(), pauser);
        meliesTokenC.grantRole(meliesTokenC.MINTER_ROLE(), minter);
        meliesTokenC.grantRole(meliesTokenC.BURNER_ROLE(), burner);
        vm.stopPrank();

        uint256 firstMint = MAX_SUPPLY / 2;
        uint256 secondMint = MAX_SUPPLY - firstMint;

        vm.startPrank(minter);
        meliesTokenC.mint(user3, firstMint);
        meliesTokenC.mint(user, secondMint);
        vm.stopPrank();

        assertEq(meliesTokenC.totalSupply(), MAX_SUPPLY);
    }

    function test_ContractAddressOperations() public {
        address contractAddress = address(0x1234567890123456789012345678901234567890);

        // Test minting to contract address
        vm.prank(minter);
        meliesToken.mint(contractAddress, 1000);
        assertEq(meliesToken.balanceOf(contractAddress), 1000);

        // Test burning from contract address
        vm.prank(burner);
        meliesToken.burn(contractAddress, 500);
        assertEq(meliesToken.balanceOf(contractAddress), 500);

        // Test transfer to contract address
        vm.prank(minter);
        meliesToken.mint(user, 1000);
        vm.prank(user);
        meliesToken.transfer(contractAddress, 300);
        assertEq(meliesToken.balanceOf(contractAddress), 800);
        assertEq(meliesToken.balanceOf(user), 700);

        // Test approve for contract address
        vm.prank(user);
        meliesToken.approve(contractAddress, 500);
        assertEq(meliesToken.allowance(user, contractAddress), 500);
    }

    function test_RoleManagementWithZeroAddress() public {
        vm.prank(admin);
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(0));
        assertTrue(meliesToken.hasRole(meliesToken.MINTER_ROLE(), address(0)));

        vm.prank(admin);
        meliesToken.revokeRole(meliesToken.MINTER_ROLE(), address(0));
        assertFalse(meliesToken.hasRole(meliesToken.MINTER_ROLE(), address(0)));
    }

    function test_PauseUnpauseWithRoleChanges() public {
        // Grant pause role to user
        vm.prank(admin);
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), user);

        // User can now pause
        vm.prank(user);
        meliesToken.pause();
        assertTrue(meliesToken.paused());

        // Revoke pause role from user
        vm.prank(admin);
        meliesToken.revokeRole(meliesToken.PAUSER_ROLE(), user);

        // User can no longer unpause
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_SELECTOR, user, meliesToken.PAUSER_ROLE()));
        vm.prank(user);
        meliesToken.unpause();

        // Admin can still unpause
        vm.prank(admin);
        meliesToken.grantRole(meliesToken.PAUSER_ROLE(), admin);
        vm.prank(admin);
        meliesToken.unpause();
        assertFalse(meliesToken.paused());
    }

    function test_CustomErrorParameters() public {
        uint256 currentSupply = 500;
        uint256 attemptToMint = MAX_SUPPLY - currentSupply + 1;

        vm.prank(minter);
        meliesToken.mint(user, currentSupply);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(Melies.ERC20MarketCapExceeded.selector, attemptToMint, currentSupply));
        meliesToken.mint(user2, attemptToMint);
    }

    function test_DomainSeparatorConsistency() public {
        Melies token1 = new Melies(admin);
        Melies token2 = new Melies(user);

        // Domain separators should be different for different contracts
        assertTrue(token1.DOMAIN_SEPARATOR() != token2.DOMAIN_SEPARATOR());

        // But role hashes should be the same
        assertEq(token1.PAUSER_ROLE(), token2.PAUSER_ROLE());
        assertEq(token1.MINTER_ROLE(), token2.MINTER_ROLE());
        assertEq(token1.BURNER_ROLE(), token2.BURNER_ROLE());
    }
}
