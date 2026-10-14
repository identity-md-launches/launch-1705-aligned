// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Aligned (ALIGN)
/// @notice Fixed-supply ERC-20 with all tokens minted once to the constructor caller.
contract Aligned is ERC20 {
    /// @notice One billion tokens expressed in 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Aligned", "ALIGN") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
