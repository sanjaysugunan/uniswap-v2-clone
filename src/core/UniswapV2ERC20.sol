// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

// OZ imports
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title UniswapV2ERC20
 * @author Sanjay Sugunan
 * @notice ERC20 implementation for Uniswap V2 Liquidity Provider (LP) tokens.
 * @dev Extends OpenZeppelin's ERC20 and ERC20Permit contracts to provide
 *      transferable LP tokens with EIP-2612 permit support for gasless approvals.
 *      Each UniswapV2Pair contract inherits from this contract.
 */
abstract contract UniswapV2ERC20 is ERC20, ERC20Permit {
    constructor() ERC20("UNI-V2", "UNI-V2") ERC20Permit("UNI-V2") {}
}
