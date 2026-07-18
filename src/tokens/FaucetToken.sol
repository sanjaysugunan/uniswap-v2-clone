// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Simple ERC20 token with a faucet.
/// @dev Anyone can mint exactly 10 tokens (10e18) to themselves.
contract FaucetToken is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 10 ether;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /// @notice Mint 10 tokens to the caller.
    function mint() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
