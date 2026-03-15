// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";

contract TestTokenTest is Test {
    TestToken public token;
    address public alice = address(0x1111111111111111111111111111111111111111);
    address public bob = address(0x2222222222222222222222222222222222222222);

    function setUp() public {
        token = new TestToken("Test Token", "TEST", 1_000_000 * 10**18);
    }

    function test_InitialState() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000 * 10**18);
        assertEq(token.balanceOf(address(this)), 1_000_000 * 10**18);
    }

    function test_Transfer() public {
        uint256 amount = 1000 * 10**18;
        bool success = token.transfer(alice, amount);

        assertTrue(success);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), 1_000_000 * 10**18 - amount);
    }

    function test_TransferEvent() public {
        uint256 amount = 1000 * 10**18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), alice, amount);

        token.transfer(alice, amount);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function test_Approval() public {
        uint256 amount = 5000 * 10**18;
        bool success = token.approve(alice, amount);

        assertTrue(success);
        assertEq(token.allowance(address(this), alice), amount);
    }

    function test_ApprovalEvent() public {
        uint256 amount = 5000 * 10**18;

        vm.expectEmit(true, true, false, true);
        emit Approval(address(this), alice, amount);

        token.approve(alice, amount);
    }

    function test_TransferFrom() public {
        uint256 amount = 1000 * 10**18;

        // Approve alice to spend tokens
        token.approve(alice, amount);

        // Transfer from this contract to bob via alice
        vm.prank(alice);
        bool success = token.transferFrom(address(this), bob, amount);

        assertTrue(success);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(address(this), alice), 0);
    }

    function test_RevertWhen_TransferInsufficientBalance() public {
        vm.expectRevert("Insufficient balance");
        token.transfer(alice, 2_000_000 * 10**18); // More than supply
    }

    function test_RevertWhen_TransferFromInsufficientAllowance() public {
        vm.expectRevert("Insufficient allowance");
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1000 * 10**18); // No allowance
    }
}
