// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Aligned} from "src/Aligned.sol";

/// forge-config: default.fuzz.runs = 1000
contract AlignedAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Aligned private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Aligned();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_MaximumTransferAmountsRevertWithoutOverflowOrAllowanceLoss() public {
        uint256 maximum = type(uint256).max;
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(error);
        token.transfer(alice, maximum);

        token.approve(spender, maximum);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneApprovalIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
    }

    function test_DelegatedSelfTransferConsumesPermissionAndCannotBeReplayed() public {
        token.approve(spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(0), uint256(1))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresEnoughBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, uint256(1), uint256(2))
        );
        vm.prank(alice);
        token.transfer(alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_OwnerCallingTransferFromNeedsSelfApproval() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), uint256(0), uint256(1)
            )
        );
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 0);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_FullSupplyDelegatedTransferExhaustsAllowance() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);

        // Replenishing the owner's balance must not replenish the exhausted allowance.
        vm.prank(alice);
        token.transfer(address(this), 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(0), uint256(1))
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), 1);
        assertEq(token.balanceOf(alice), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_InfiniteAllowanceSurvivesEmptyBalanceAndCanBeReplacedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), uint256(0), uint256(1)
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        vm.prank(alice);
        token.transfer(address(this), 3);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(1), uint256(2))
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 2);
        assertEq(token.allowance(address(this), spender), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);

        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(0), uint256(1))
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), 1);
        assertEq(token.balanceOf(alice), SUPPLY - 3);
        assertEq(token.balanceOf(bob), 2);
    }

    function test_DeployerCannotClawBackDistributedTokens() public {
        token.transfer(alice, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), uint256(0), SUPPLY)
        );
        token.transferFrom(alice, address(this), SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_ZeroDelegatedTransferEmitsButZeroRecipientStillReverts() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));

        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderRejectsZeroAndMaximumApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_TransferRoundTripPreservesBalancesAndPermissions(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, approval);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitSpendingHasSameNetEffect(uint256 amount, uint256 first, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        approval = bound(approval, amount, type(uint256).max);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount - first));

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 oldLimit, uint256 newLimit) public {
        token.approve(spender, oldLimit);
        token.approve(bob, oldLimit);
        vm.prank(alice);
        token.approve(spender, oldLimit);

        token.approve(spender, newLimit);
        token.approve(spender, newLimit);
        assertEq(token.allowance(address(this), spender), newLimit);
        assertEq(token.allowance(address(this), bob), oldLimit);
        assertEq(token.allowance(alice, spender), oldLimit);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedBalanceCheckPreservesFiniteAllowance(uint256 balance, uint256 requested) public {
        balance = bound(balance, 0, SUPPLY);
        requested = bound(requested, balance + 1, type(uint256).max - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, requested);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);

        assertEq(token.allowance(alice, spender), requested);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceFailsEvenWithSufficientBalance(
        uint256 balance,
        uint256 approved,
        uint256 requested
    ) public {
        balance = bound(balance, 1, SUPPLY);
        approved = bound(approved, 0, balance - 1);
        requested = bound(requested, approved + 1, balance);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);

        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverPreservesFiniteOrInfiniteAllowance(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
