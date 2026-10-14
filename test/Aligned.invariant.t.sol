// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Aligned} from "src/Aligned.sol";
import {AlignedHandler} from "./helpers/AlignedHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract AlignedInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Aligned private token;
    AlignedHandler private handler;
    address[5] private actors;

    function setUp() public {
        token = new Aligned();
        actors = [
            address(this),
            makeAddr("holder one"),
            makeAddr("holder two"),
            makeAddr("holder three"),
            makeAddr("empty holder")
        ];
        uint256[5] memory balances = [SUPPLY / 4, SUPPLY / 4, SUPPLY / 4, SUPPLY / 4, uint256(0)];
        for (uint256 i = 1; i < 4; ++i) {
            assertTrue(token.transfer(actors[i], balances[i]));
        }
        handler = new AlignedHandler(token, actors, balances);

        // Start with usable finite and infinite approvals so delegated calls can move value
        // immediately. Later calls may replace, revoke, exhaust or reuse any permission.
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY);
        }
        handler.approveUnlimited(0, 2);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.approveUnlimited.selector;
        selectors[3] = handler.revoke.selector;
        selectors[4] = handler.transferFrom.selector;
        selectors[5] = handler.transferBeyondBalance.selector;
        selectors[6] = handler.transferFromBeyondAllowance.selector;
        selectors[7] = handler.transferFromBeyondBalance.selector;
        selectors[8] = handler.transferToZero.selector;
        selectors[9] = handler.approveZero.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyEqualsAllHolderBalances() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        assertEq(sum, SUPPLY, "tokens escaped or were created in the closed holder set");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
    }

    function invariant_eachBalanceMatchesRequestedFlows() public view {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            assertEq(
                handler.initialBalance(actor) + handler.received(actor),
                token.balanceOf(actor) + handler.sent(actor),
                "holder was credited or debited an incorrect amount"
            );
        }
    }

    function invariant_onlyApprovedSpendingConsumesAllowance() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "permission changed outside its owner's approvals and successful spends"
                );
            }
        }
    }

    /// @dev A deterministic witness that the handler reaches nonzero transfers, aliased
    /// addresses, allowance replacement, and every expected failure without skipping calls.
    function test_HandlerExercisesTransfersAndExpectedFailures() public {
        handler.transfer(0, 1, 1);
        handler.transferFrom(0, 2, 4, 1);
        handler.approve(1, 2, 7);
        handler.transferFrom(1, 2, 1, 3);
        assertEq(token.allowance(actors[1], actors[2]), 4);
        handler.revoke(1, 2);
        handler.transferBeyondBalance(4, 4, type(uint256).max);
        handler.transferFromBeyondAllowance(1, 2, 4, 0);
        handler.transferFromBeyondBalance(4, 2, 1, 2, false);
        handler.transferFromBeyondBalance(4, 2, 1, type(uint256).max, true);
        handler.transferToZero(1, 2, 1, true);
        handler.transferToZero(1, 2, 0, false);
        handler.approveZero(1, type(uint256).max);

        assertEq(token.balanceOf(actors[0]), SUPPLY / 4 - 2);
        assertEq(token.balanceOf(actors[1]), SUPPLY / 4 + 1);
        assertEq(token.balanceOf(actors[4]), 1);
        invariant_fixedSupplyEqualsAllHolderBalances();
        invariant_eachBalanceMatchesRequestedFlows();
        invariant_onlyApprovedSpendingConsumesAllowance();
    }
}
