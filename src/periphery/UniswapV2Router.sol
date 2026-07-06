// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../libraries/UniswapV2Library.sol";
import {IUniswapV2Pair} from "../core/UniswapV2Pair.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
// OZ imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniswapV2Router
 * @author Sanjay Sugunan
 * @notice Provides the primary interface for interacting with Uniswap V2 liquidity pools.
 * @dev Handles liquidity management and token swaps while enforcing slippage
 *      protection, deadline checks, and optimal liquidity calculations. Uses
 *      UniswapV2Library to compute pair addresses and swap amounts.
 */
contract UniswapV2Router is IUniswapV2Router {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address private immutable i_factory;
    address private immutable i_WETH;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Ensures the transaction is executed before the specified deadline.
     * @dev Reverts if the current block timestamp exceeds the provided deadline,
     *      protecting users from executing stale transactions.
     * @param deadline The latest timestamp at which the transaction is valid.
     */
    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert UniswapV2Router__Expired();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the router with the factory and WETH contract addresses.
     * @dev Sets the immutable factory and WETH addresses used for pair lookups,
     *      liquidity management, and ETH wrapping/unwrapping.
     * @param _factory The address of the UniswapV2Factory contract.
     * @param _WETH The address of the Wrapped Ether (WETH) contract.
     */
    constructor(address _factory, address _WETH) {
        i_factory = _factory;
        i_WETH = _WETH;
    }

    /*//////////////////////////////////////////////////////////////
                            RECIEVE FUNCTION
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Receives native ETH exclusively from the WETH contract.
     * @dev Reverts if ETH is sent by any address other than the WETH contract,
     *      preventing accidental or unauthorized ETH transfers.
     */
    receive() external payable {
        if (msg.sender != i_WETH) {
            revert UniswapV2Router__OnlyWETH();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Calculates the optimal token amounts for adding liquidity.
     * @dev Creates the pair if it does not already exist and determines the
     *      optimal deposit amounts based on the current pool reserves while
     *      enforcing the user's minimum amount constraints.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param amountADesired The desired amount of tokenA to deposit.
     * @param amountBDesired The desired amount of tokenB to deposit.
     * @param amountAMin The minimum acceptable amount of tokenA.
     * @param amountBMin The minimum acceptable amount of tokenB.
     * @return amountA The actual amount of tokenA to deposit.
     * @return amountB The actual amount of tokenB to deposit.
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(i_factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(i_factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(i_factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert UniswapV2Router__InsufficientAmountB();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired); // Mathematically impossible to break
                if (amountAOptimal < amountAMin) revert UniswapV2Router__InsufficientAmountA();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /**
     * @notice Adds liquidity to a token pair and mints LP tokens.
     * @dev Determines the optimal deposit amounts, transfers the tokens to the
     *      pair contract, and mints LP tokens to the specified recipient.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param amountADesired The desired amount of tokenA to deposit.
     * @param amountBDesired The desired amount of tokenB to deposit.
     * @param amountAMin The minimum acceptable amount of tokenA.
     * @param amountBMin The minimum acceptable amount of tokenB.
     * @param to The address receiving the minted LP tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amountA The actual amount of tokenA deposited.
     * @return amountB The actual amount of tokenB deposited.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(i_factory, tokenA, tokenB);
        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, pair, amountA);
        SafeERC20.safeTransferFrom(IERC20(tokenB), msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    /**
     * @notice Adds liquidity to a token-WETH pair using native ETH.
     * @dev Wraps the supplied ETH into WETH, transfers both assets to the pair,
     *      mints LP tokens to the specified recipient, and refunds any excess ETH.
     * @param token The address of the ERC20 token.
     * @param amountTokenDesired The desired amount of the ERC20 token to deposit.
     * @param amountTokenMin The minimum acceptable amount of the ERC20 token.
     * @param amountETHMin The minimum acceptable amount of ETH.
     * @param to The address receiving the minted LP tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amountToken The actual amount of the ERC20 token deposited.
     * @return amountETH The actual amount of ETH deposited.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) =
            _addLiquidity(token, i_WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = UniswapV2Library.pairFor(i_factory, token, i_WETH);
        IWETH(i_WETH).deposit{value: amountETH}();
        if (!IWETH(i_WETH).transfer(pair, amountETH)) revert UniswapV2Router__WETHTransferFailed();
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, pair, amountToken);
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Removes liquidity from a token pair and returns the underlying assets.
     * @dev Burns the specified LP tokens, transfers the underlying tokens to the
     *      recipient, and enforces the user's minimum amount constraints.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountAMin The minimum acceptable amount of tokenA.
     * @param amountBMin The minimum acceptable amount of tokenB.
     * @param to The address receiving the underlying tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amountA The amount of tokenA returned.
     * @return amountB The amount of tokenB returned.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = UniswapV2Library.pairFor(i_factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = token0 == tokenA ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) revert UniswapV2Router__InsufficientAmountA();
        if (amountB < amountBMin) revert UniswapV2Router__InsufficientAmountB();
    }

    /**
     * @notice Removes liquidity from a token-WETH pair and returns native ETH.
     * @dev Burns the specified LP tokens, unwraps WETH into ETH, transfers the
     *      ERC20 tokens and ETH to the recipient, and enforces the user's minimum
     *      amount constraints.
     * @param token The address of the ERC20 token.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountTokenMin The minimum acceptable amount of the ERC20 token.
     * @param amountETHMin The minimum acceptable amount of ETH.
     * @param to The address receiving the underlying assets.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amountToken The amount of the ERC20 token returned.
     * @return amountETH The amount of ETH returned.
     */
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token, i_WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline
        );
        SafeERC20.safeTransfer(IERC20(token), to, amountToken);
        IWETH(i_WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /**
     * @notice Approves the router to spend LP tokens using an EIP-2612 permit signature.
     * @dev Computes the pair address, determines the approval amount, and invokes
     *      the pair's permit function to authorize LP token transfers without a
     *      separate approval transaction.
     * @param tokenA The address of the first token in the pair.
     * @param tokenB The address of the second token in the pair.
     * @param liquidity The amount of LP tokens to approve.
     * @param deadline The permit signature expiration timestamp.
     * @param approveMax Whether to approve the maximum uint256 value instead of the specified liquidity.
     * @param v The recovery byte of the ECDSA signature.
     * @param r The first 32 bytes of the ECDSA signature.
     * @param s The second 32 bytes of the ECDSA signature.
     */
    function _permitLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        address pair = UniswapV2Library.pairFor(i_factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IERC20Permit(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    /**
     * @notice Removes liquidity using an EIP-2612 permit signature for LP token approval.
     * @dev Approves the router via permit and removes the specified liquidity in a
     *      single transaction, eliminating the need for a prior approval call.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountAMin The minimum acceptable amount of tokenA.
     * @param amountBMin The minimum acceptable amount of tokenB.
     * @param to The address receiving the underlying tokens.
     * @param deadline The latest timestamp at which the transaction and permit are valid.
     * @param approveMax Whether to approve the maximum uint256 value instead of the specified liquidity.
     * @param v The recovery byte of the ECDSA signature.
     * @param r The first 32 bytes of the ECDSA signature.
     * @param s The second 32 bytes of the ECDSA signature.
     * @return amountA The amount of tokenA returned.
     * @return amountB The amount of tokenB returned.
     */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        // to avoid stack too deep errors
        _permitLiquidity(tokenA, tokenB, liquidity, deadline, approveMax, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /**
     * @notice Removes liquidity from a token-WETH pair using an EIP-2612 permit signature.
     * @dev Approves the router to spend LP tokens via permit, removes the specified
     *      liquidity, unwraps WETH into native ETH, and transfers the ERC20 tokens
     *      and ETH to the recipient in a single transaction.
     * @param token The address of the ERC20 token.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountTokenMin The minimum acceptable amount of the ERC20 token.
     * @param amountETHMin The minimum acceptable amount of ETH.
     * @param to The address receiving the underlying assets.
     * @param deadline The latest timestamp at which the transaction and permit are valid.
     * @param approveMax Whether to approve the maximum uint256 value instead of the specified liquidity.
     * @param v The recovery byte of the ECDSA signature.
     * @param r The first 32 bytes of the ECDSA signature.
     * @param s The second 32 bytes of the ECDSA signature.
     * @return amountToken The amount of the ERC20 token returned.
     * @return amountETH The amount of native ETH returned.
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        // to avoid stack too deep errors
        _permitLiquidity(token, i_WETH, liquidity, deadline, approveMax, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                                  SWAP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Executes a multi-hop token swap along the specified path.
     * @dev Iterates through each pair in the swap path, forwarding the output
     *      tokens from one pair to the next until the final recipient receives
     *      the output tokens.
     * @param amounts The amounts to swap at each step of the path.
     * @param path The sequence of token addresses defining the swap route.
     * @param _to The final recipient of the output tokens.
     */
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(i_factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(i_factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * @dev Computes the output amounts for the specified path, enforces the minimum
     *      output constraint, transfers the input tokens to the first pair, and
     *      executes the multi-hop swap.
     * @param amountIn The exact amount of input tokens to swap.
     * @param amountOutMin The minimum acceptable amount of output tokens.
     * @param path The sequence of token addresses defining the swap route.
     * @param to The address receiving the output tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amounts The amount of tokens exchanged at each step of the swap path.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(i_factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert UniswapV2Router__InsufficientOutputAmount();
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(i_factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    /**
     * @notice Swaps tokens to receive an exact amount of output tokens.
     * @dev Computes the required input amounts for the specified path, enforces
     *      the maximum input constraint, transfers the input tokens to the first
     *      pair, and executes the multi-hop swap.
     * @param amountOut The exact amount of output tokens to receive.
     * @param amountInMax The maximum acceptable amount of input tokens.
     * @param path The sequence of token addresses defining the swap route.
     * @param to The address receiving the output tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amounts The amount of tokens exchanged at each step of the swap path.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(i_factory, amountOut, path);
        if (amounts[0] > amountInMax) revert UniswapV2Router__ExcessiveInputAmount();
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(i_factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    /**
     * @notice Swaps an exact amount of native ETH for as many output tokens as possible.
     * @dev Wraps the supplied ETH into WETH, transfers it to the first pair,
     *      computes the output amounts, enforces the minimum output constraint,
     *      and executes the multi-hop swap.
     * @param amountOutMin The minimum acceptable amount of output tokens.
     * @param path The sequence of token addresses defining the swap route. The first token must be WETH.
     * @param to The address receiving the output tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amounts The amount of tokens exchanged at each step of the swap path.
     */
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != i_WETH) revert UniswapV2Router__InvalidPath();
        amounts = UniswapV2Library.getAmountsOut(i_factory, msg.value, path);
        if (amounts[path.length - 1] < amountOutMin) revert UniswapV2Router__InsufficientOutputAmount();
        IWETH(i_WETH).deposit{value: amounts[0]}();
        if (!IWETH(i_WETH).transfer(UniswapV2Library.pairFor(i_factory, path[0], path[1]), amounts[0])) {
            revert UniswapV2Router__WETHTransferFailed();
        }
        _swap(amounts, path, to);
    }

    /**
     * @notice Swaps tokens to receive an exact amount of native ETH.
     * @dev Computes the required input amounts, transfers the input tokens to the
     *      first pair, executes the multi-hop swap, unwraps WETH into ETH, and
     *      transfers the ETH to the recipient. Reverts if the required input
     *      exceeds the specified maximum.
     * @param amountOut The exact amount of ETH to receive.
     * @param amountInMax The maximum acceptable amount of input tokens.
     * @param path The sequence of token addresses defining the swap route. The last token must be WETH.
     * @param to The address receiving the native ETH.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amounts The amount of tokens exchanged at each step of the swap path.
     */
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != i_WETH) revert UniswapV2Router__InvalidPath();
        amounts = UniswapV2Library.getAmountsIn(i_factory, amountOut, path);
        if (amounts[0] > amountInMax) revert UniswapV2Router__ExcessiveInputAmount();
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(i_factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(i_WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /**
     * @notice Swaps an exact amount of input tokens for as much native ETH as possible.
     * @dev Computes the output amounts, transfers the input tokens to the first
     *      pair, executes the multi-hop swap, unwraps WETH into ETH, and transfers
     *      the ETH to the recipient. Reverts if the output ETH is less than the
     *      specified minimum.
     * @param amountIn The exact amount of input tokens to swap.
     * @param amountOutMin The minimum acceptable amount of ETH.
     * @param path The sequence of token addresses defining the swap route. The last token must be WETH.
     * @param to The address receiving the native ETH.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amounts The amount of tokens exchanged at each step of the swap path.
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != i_WETH) revert UniswapV2Router__InvalidPath();
        amounts = UniswapV2Library.getAmountsOut(i_factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert UniswapV2Router__InsufficientOutputAmount();
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(i_factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(i_WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /**
     * @notice Swaps native ETH for an exact amount of output tokens.
     * @dev Wraps the required ETH into WETH, transfers it to the first pair,
     *      executes the multi-hop swap, and refunds any excess ETH to the sender.
     *      Reverts if the required ETH exceeds the amount sent.
     * @param amountOut The exact amount of output tokens to receive.
     * @param path The sequence of token addresses defining the swap route. The first token must be WETH.
     * @param to The address receiving the output tokens.
     * @param deadline The latest timestamp at which the transaction is valid.
     * @return amounts The amount of tokens exchanged at each step of the swap path.
     */
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != i_WETH) revert UniswapV2Router__InvalidPath();
        amounts = UniswapV2Library.getAmountsIn(i_factory, amountOut, path);
        if (amounts[0] > msg.value) revert UniswapV2Router__ExcessiveInputAmount();
        IWETH(i_WETH).deposit{value: amounts[0]}();
        if (!IWETH(i_WETH).transfer(UniswapV2Library.pairFor(i_factory, path[0], path[1]), amounts[0])) {
            revert UniswapV2Router__WETHTransferFailed();
        }
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function factory() external view override returns (address) {
        return i_factory;
    }

    function WETH() external view override returns (address) {
        return i_WETH;
    }

    /*//////////////////////////////////////////////////////////////
                           LIBRARY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        external
        pure
        override
        returns (uint256 amountB)
    {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        override
        returns (uint256 amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        override
        returns (uint256 amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(i_factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(i_factory, amountOut, path);
    }
}
