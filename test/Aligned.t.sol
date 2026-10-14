// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Aligned} from "../src/Aligned.sol";

/// @dev A local factory, not a production deployment configuration.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (Aligned) {
        return new Aligned{salt: salt}();
    }
}

contract AlignedTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Aligned private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new Aligned();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Aligned");
        assertEq(token.symbol(), "ALIGN");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new Aligned();
    }

    function test_Create2MintsEntireSupplyToFactory() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        Aligned deployed = factory.deploy(keccak256("Aligned launch"));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_TransferEmitsAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 100 ether);
        assertTrue(token.transfer(alice, 100 ether));
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferToZeroEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, uint256(0), uint256(1))
        );
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferMoreThanSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveEmitsOverwritesAndRevokes() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 60 ether);
    }

    function test_InfiniteAllowanceIsPreserved() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_RevertTransferFromWithoutAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(0), uint256(1))
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertTransferFromExceedingAllowance() public {
        token.approve(spender, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(1), uint256(2))
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertTransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, uint256(0), uint256(10))
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferFromToZeroRollsBackAllowance() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferFromZeroSender() public {
        // Allowance handling rejects a zero approver before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_ApprovalCannotBeUsedByOtherCaller() public {
        token.approve(spender, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, uint256(0), uint256(100))
        );
        vm.prank(bob);
        token.transferFrom(address(this), bob, 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevokedApprovalCannotSpend() public {
        token.approve(spender, 100);
        token.approve(spender, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(0), uint256(1))
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_NoMintBurnFreezeOrUpgradeEntryPoints() public {
        token.transfer(alice, 100 ether);
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[3] = abi.encodeWithSignature("pause()");
        calls[4] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[5] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[6] = abi.encodeWithSignature("initialize(address)", bob);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_TransferToContractNeedsNoReceiverHook() public {
        TokenFactoryProbe receiver = new TokenFactoryProbe();
        assertTrue(token.transfer(address(receiver), 1 ether));
        assertEq(token.balanceOf(address(receiver)), 1 ether);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromTracksAllowance(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.allowance(address(this), spender), approved - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverspendingRevertsWithoutMutation(uint256 approved) public {
        approved = bound(approved, 0, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, approved + 1);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    /// @dev Exercise mixed operations, including self-transfers, over a closed set of holders.
    function testFuzz_MixedOperationSequenceConservesSupply(bytes32 seed) public {
        address[4] memory holders = [address(this), alice, bob, spender];
        for (uint256 i; i < 32; ++i) {
            uint256 random = uint256(keccak256(abi.encode(seed, i)));
            address from = holders[random % 4];
            address to = holders[(random >> 8) % 4];
            uint256 amount = (random >> 16) % (token.balanceOf(from) + 1);
            if (random & 1 == 0) {
                vm.prank(from);
                assertTrue(token.transfer(to, amount));
            } else {
                vm.prank(from);
                assertTrue(token.approve(spender, amount));
                vm.prank(spender);
                assertTrue(token.transferFrom(from, to, amount));
                assertEq(token.allowance(from, spender), 0);
            }
            uint256 sum;
            for (uint256 j; j < holders.length; ++j) {
                sum += token.balanceOf(holders[j]);
            }
            assertEq(sum, SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }
}
