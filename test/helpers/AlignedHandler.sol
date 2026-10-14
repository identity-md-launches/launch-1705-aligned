// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Aligned} from "src/Aligned.sol";

/// @dev All transfers stay within five actors, including the original deployer.
/// The ledger records requested flows; it never copies the token's balances or allowances.
contract AlignedHandler is Test {
    Aligned public immutable token;
    address[5] public actors;
    mapping(address => uint256) public initialBalance;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public lastApproval;
    mapping(address => mapping(address => uint256)) public spentSinceApproval;

    constructor(Aligned token_, address[5] memory actors_, uint256[5] memory balances_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            initialBalance[actors_[i]] = balances_[i];
        }
    }

    function expectedBalance(address owner) public view returns (uint256) {
        return initialBalance[owner] + received[owner] - sent[owner];
    }

    function expectedAllowance(address owner, address spender) public view returns (uint256) {
        uint256 approved = lastApproval[owner][spender];
        return approved == type(uint256).max ? approved : approved - spentSinceApproval[owner][spender];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
    }

    // Raw uint256 approvals cover values above supply as well as ordinary spending limits.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function approveUnlimited(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), 0);
    }

    /// @dev Uses existing permissions, so approvals, revocations and spends can interleave.
    /// Actor selection deliberately permits owner == spender, from == to, and all three equal.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance(owner, spender);
        uint256 available = expectedBalance(owner);
        uint256 amount = bound(amountSeed, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        if (allowed != type(uint256).max) spentSinceApproval[owner][spender] += amount;
        _recordTransfer(owner, to, amount);
    }

    function transferBeyondBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ledger update: all balances and permissions must survive the failed call.
    }

    function transferFromBeyondAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 limitSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 limit = bound(limitSeed, 0, expectedBalance(owner));
        _approve(owner, spender, limit);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, limit, limit + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, limit + 1);
    }

    function transferFromBeyondBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // In particular, a failed transfer must not consume the freshly granted permission.
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance(owner));
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function approveZero(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        lastApproval[owner][spender] = amount;
        spentSinceApproval[owner][spender] = 0;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
    }
}
