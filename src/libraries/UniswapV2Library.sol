// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {UniswapV2Pair} from "../core/UniswapV2Pair.sol";
// Oz imports
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title UniswapV2Library
 * @author Sanjay Sugunan
 * @notice Provides pure and view helper functions for Uniswap V2 operations.
 * @dev Contains utility functions for deterministic pair address computation,
 *      reserve retrieval, liquidity quoting, and swap amount calculations used
 *      by the router.
 */
library UniswapV2Library {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UniswapV2Library__IdenticalAddresses();
    error UniswapV2Library__ZeroAddress();
    error UniswapV2Library__InsufficientLiquidity();
    error UniswapV2Library__InsufficientAmount();
    error UniswapV2Library__InsufficientInputAmount();
    error UniswapV2Library__InsufficientOutputAmount();
    error UniswapV2Library__InvalidPath();

    /**
     * @notice Returns the token addresses in ascending order.
     * @dev Ensures a consistent token ordering across the protocol for deterministic
     *      pair address computation and reserve lookups. Reverts if the token
     *      addresses are identical or either address is the zero address.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return token0 The token with the lower address.
     * @return token1 The token with the higher address.
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert UniswapV2Library__IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert UniswapV2Library__ZeroAddress();
    }

    /**
     * @notice Computes the deterministic address of a pair contract.
     * @dev Uses CREATE2 with the factory address, sorted token addresses, and the
     *      pair contract's creation code hash to derive the pair address without
     *      performing any external calls.
     * @param factory The address of the UniswapV2Factory contract.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pair The deterministic address of the pair contract.
     */
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 bytecodeHash = keccak256(type(UniswapV2Pair).creationCode);
        pair = Create2.computeAddress(salt, bytecodeHash, factory);
    }

    /**
     * @notice Returns the reserves for a token pair in the order of the input tokens.
     * @dev Fetches the reserves from the corresponding pair contract and reorders
     *      them to match the order of `tokenA` and `tokenB`, regardless of the
     *      pair's internal token ordering.
     * @param factory The address of the UniswapV2Factory contract.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return reserveA The reserve corresponding to `tokenA`.
     * @return reserveB The reserve corresponding to `tokenB`.
     */
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @notice Returns the equivalent amount of one asset given the reserves of a pair.
     * @dev Computes the proportional amount of the second asset required to maintain
     *      the current reserve ratio. Reverts if the input amount or either reserve
     *      is zero.
     * @param amountA The amount of the first asset.
     * @param reserveA The reserve of the first asset.
     * @param reserveB The reserve of the second asset.
     * @return amountB The equivalent amount of the second asset.
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert UniswapV2Library__InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert UniswapV2Library__InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    /**
     * @notice Returns the maximum output amount for a given input amount.
     * @dev Calculates the output amount using the constant product formula and
     *      accounts for the protocol's swap fee. Reverts if the input amount or
     *      either reserve is zero.
     * @param amountIn The amount of input tokens.
     * @param reserveIn The reserve of the input token.
     * @param reserveOut The reserve of the output token.
     * @return amountOut The maximum amount of output tokens obtainable.
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert UniswapV2Library__InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert UniswapV2Library__InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Returns the minimum input amount required for a desired output amount.
     * @dev Calculates the required input amount using the constant product formula
     *      and accounts for the protocol's swap fee. Reverts if the output amount
     *      is zero, the reserves are zero, or the requested output exceeds the
     *      available reserve.
     * @param amountOut The desired amount of output tokens.
     * @param reserveIn The reserve of the input token.
     * @param reserveOut The reserve of the output token.
     * @return amountIn The minimum amount of input tokens required.
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) revert UniswapV2Library__InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert UniswapV2Library__InsufficientLiquidity();
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /**
     * @notice Returns the output amounts for each hop in a swap path.
     * @dev Performs chained `getAmountOut` calculations across all pairs in the
     *      specified path using the current reserves. Reverts if the path contains
     *      fewer than two tokens.
     * @param factory The address of the UniswapV2Factory contract.
     * @param amountIn The amount of input tokens.
     * @param path The sequence of token addresses defining the swap route.
     * @return amounts The output amount at each step of the swap path.
     */
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert UniswapV2Library__InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
     * @notice Returns the input amounts required for each hop in a swap path.
     * @dev Performs chained `getAmountIn` calculations across all pairs in the
     *      specified path using the current reserves. Reverts if the path contains
     *      fewer than two tokens.
     * @param factory The address of the UniswapV2Factory contract.
     * @param amountOut The desired amount of output tokens.
     * @param path The sequence of token addresses defining the swap route.
     * @return amounts The required input amount at each step of the swap path.
     */
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert UniswapV2Library__InvalidPath();
        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
