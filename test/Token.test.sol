// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./mocks/MockERC20.sol";

/**
 * @title TokenTest
 * @dev Comprehensive test suite for ERC20 token functionality
 */
contract TokenTest is Test {
    // Events to check emissions
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // Test addresses
    address private owner;
    address private user1;
    address private user2;
    address private zeroAddress = address(0);

    // Token instance
    MockERC20 private token;

    // Test values
    string private constant TOKEN_NAME = "Pharos Token";
    string private constant TOKEN_SYMBOL = "PHT";
    uint8 private constant TOKEN_DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 private constant TRANSFER_AMOUNT = 1000 * 10**18;

    function setUp() public {
        // Set up accounts
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        vm.startPrank(owner);
        
        // Deploy token
        token = new MockERC20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS);
        
        // Mint initial supply to owner
        token.mint(owner, INITIAL_SUPPLY);
        
        vm.stopPrank();
    }

    // ==================== DEPLOYMENT TESTS ====================

    function testTokenDeployment() public view {
        // Test basic token properties
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.decimals(), TOKEN_DECIMALS);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    // ==================== TRANSFER TESTS ====================

    function testTransfer() public {
        vm.startPrank(owner);
        
        // Expect Transfer event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, TRANSFER_AMOUNT);
        
        // Transfer tokens
        bool success = token.transfer(user1, TRANSFER_AMOUNT);
        
        // Assertions
        assertTrue(success);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user1), TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testTransferExceedingBalance() public {
        vm.startPrank(user1);
        
        // User1 has no tokens, so this should fail with ERC20InsufficientBalance error
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", user1, 0, TRANSFER_AMOUNT));
        token.transfer(user2, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testTransferToZeroAddress() public {
        vm.startPrank(owner);
        
        // Transfer to zero address should fail with ERC20InvalidReceiver error
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        token.transfer(zeroAddress, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testMultipleTransfers() public {
        vm.startPrank(owner);
        
        // First transfer
        token.transfer(user1, TRANSFER_AMOUNT);
        
        // Second transfer
        token.transfer(user2, TRANSFER_AMOUNT * 2);
        
        // Assertions
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - TRANSFER_AMOUNT * 3);
        assertEq(token.balanceOf(user1), TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2), TRANSFER_AMOUNT * 2);
        
        vm.stopPrank();
    }

    // ==================== APPROVE TESTS ====================

    function testApprove() public {
        vm.startPrank(owner);
        
        // Expect Approval event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Approval(owner, user1, TRANSFER_AMOUNT);
        
        // Approve tokens
        bool success = token.approve(user1, TRANSFER_AMOUNT);
        
        // Assertions
        assertTrue(success);
        assertEq(token.allowance(owner, user1), TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testApproveToZeroAddress() public {
        vm.startPrank(owner);
        
        // Approve zero address should fail with ERC20InvalidSpender error
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidSpender(address)", address(0)));
        token.approve(zeroAddress, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testIncreaseAllowance() public {
        vm.startPrank(owner);
        
        // Initial approval
        token.approve(user1, TRANSFER_AMOUNT);
        
        // Increase allowance by another TRANSFER_AMOUNT
        bool success = token.increaseAllowance(user1, TRANSFER_AMOUNT);
        
        // Assertions
        assertTrue(success);
        assertEq(token.allowance(owner, user1), TRANSFER_AMOUNT * 2);
        
        vm.stopPrank();
    }

    function testDecreaseAllowance() public {
        vm.startPrank(owner);
        
        // Initial approval for double the amount
        token.approve(user1, TRANSFER_AMOUNT * 2);
        
        // Decrease allowance by TRANSFER_AMOUNT
        bool success = token.decreaseAllowance(user1, TRANSFER_AMOUNT);
        
        // Assertions
        assertTrue(success);
        assertEq(token.allowance(owner, user1), TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testDecreaseAllowanceBelowZero() public {
        vm.startPrank(owner);
        
        // Initial approval
        token.approve(user1, TRANSFER_AMOUNT);
        
        // Decrease allowance by more than approved should fail with custom error message
        vm.expectRevert("ERC20: decreased allowance below zero");
        token.decreaseAllowance(user1, TRANSFER_AMOUNT * 2);
        
        vm.stopPrank();
    }

    // ==================== TRANSFER FROM TESTS ====================

    function testTransferFrom() public {
        // Setup: owner approves user1 to spend tokens
        vm.prank(owner);
        token.approve(user1, TRANSFER_AMOUNT);
        
        vm.startPrank(user1);
        
        // Expect Transfer event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user2, TRANSFER_AMOUNT);
        
        // Transfer tokens from owner to user2
        bool success = token.transferFrom(owner, user2, TRANSFER_AMOUNT);
        
        // Assertions
        assertTrue(success);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2), TRANSFER_AMOUNT);
        assertEq(token.allowance(owner, user1), 0);
        
        vm.stopPrank();
    }

    function testTransferFromWithoutApproval() public {
        vm.startPrank(user1);
        
        // Attempt to transfer without approval should fail with ERC20InsufficientAllowance error
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", user1, 0, TRANSFER_AMOUNT));
        token.transferFrom(owner, user2, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testTransferFromExceedingAllowance() public {
        // Setup: owner approves user1 for less than transfer amount
        vm.prank(owner);
        token.approve(user1, TRANSFER_AMOUNT / 2);
        
        vm.startPrank(user1);
        
        // Attempt to transfer more than allowed should fail with ERC20InsufficientAllowance error
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", user1, TRANSFER_AMOUNT / 2, TRANSFER_AMOUNT));
        token.transferFrom(owner, user2, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testTransferFromExceedingBalance() public {
        // Setup: owner approves user1, but then transfers out tokens
        vm.startPrank(owner);
        token.approve(user1, TRANSFER_AMOUNT);
        
        // Transfer all but TRANSFER_AMOUNT/2 tokens away
        token.transfer(user2, INITIAL_SUPPLY - TRANSFER_AMOUNT / 2);
        
        // Check the remaining balance
        uint256 remainingBalance = token.balanceOf(owner);
        assertEq(remainingBalance, TRANSFER_AMOUNT / 2);
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Attempt to transfer more than owner's balance should fail with ERC20InsufficientBalance error
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", owner, TRANSFER_AMOUNT / 2, TRANSFER_AMOUNT));
        token.transferFrom(owner, user1, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    // ==================== MINT TESTS ====================

    function testMint() public {
        vm.startPrank(owner);
        
        // Initial total supply
        uint256 initialSupply = token.totalSupply();
        
        // Expect Transfer event to be emitted (from zero address)
        vm.expectEmit(true, true, false, true);
        emit Transfer(zeroAddress, user1, TRANSFER_AMOUNT);
        
        // Mint tokens to user1
        token.mint(user1, TRANSFER_AMOUNT);
        
        // Assertions
        assertEq(token.totalSupply(), initialSupply + TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user1), TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    function testMintToZeroAddress() public {
        vm.startPrank(owner);
        
        // Mint to zero address should fail with ERC20InvalidReceiver error
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        token.mint(zeroAddress, TRANSFER_AMOUNT);
        
        vm.stopPrank();
    }

    // ==================== MISCELLANEOUS TESTS ====================

    function testTransferFullBalance() public {
        vm.startPrank(owner);
        
        // Transfer entire balance to user1
        token.transfer(user1, INITIAL_SUPPLY);
        
        // Assertions
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(user1), INITIAL_SUPPLY);
        
        vm.stopPrank();
    }

    function testInfiniteApproval() public {
        vm.startPrank(owner);
        
        // Approve maximum uint256 value
        token.approve(user1, type(uint256).max);
        
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Transfer some tokens
        token.transferFrom(owner, user2, TRANSFER_AMOUNT);
        
        // Allowance should remain unchanged when approving maximum value
        assertEq(token.allowance(owner, user1), type(uint256).max);
        
        vm.stopPrank();
    }

    function testTransactionGasUsage() public {
        vm.startPrank(owner);
        
        // Measure gas usage for a transfer
        uint256 gasBefore = gasleft();
        token.transfer(user1, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Gas usage should be reasonable (varies by implementation)
        // This is more of a benchmark than a hard assertion
        assertTrue(gasUsed < 60000);
        
        vm.stopPrank();
    }
}

