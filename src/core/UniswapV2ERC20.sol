// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

// OZ imports
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

abstract contract UniswapV2ERC20 is ERC20, ERC20Permit {
    constructor() ERC20("UNI-V2", "UNI-V2") ERC20Permit("UNI-V2") {}
}
