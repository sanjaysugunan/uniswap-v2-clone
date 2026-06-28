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

contract UniswapV2Router is IUniswapV2Router {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address private immutable i_factory;
    address private immutable i_WETH;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert UniswapV2Router__Expired();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address _factory, address _WETH) {
        i_factory = _factory;
        i_WETH = _WETH;
    }

    // try to understand this
    receive() external payable {
        if (msg.sender != i_WETH) {
            revert UniswapV2Router__OnlyWETH(); // only accept ETH via fallback from the WETH contract
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/
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
                if (amountBOptimal < amountBMin) revert UniswapV2Router__InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired); // Mathematically impossible to break
                if (amountAOptimal < amountAMin) revert UniswapV2Router__InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

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
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/
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
        if (amountA < amountAMin) revert UniswapV2Router__InsufficientAAmount();
        if (amountB < amountBMin) revert UniswapV2Router__InsufficientBAmount();
    }

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
        TransferHelper.safeTransferETH(to, amountToken);
    }

    // to avoid stack too deep errors
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
        // address pair = UniswapV2Library.pairFor(i_factory, tokenA, tokenB);
        // uint256 value = approveMax ? type(uint256).max : liquidity;
        // IERC20Permit(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        _permitLiquidity(tokenA, tokenB, liquidity, deadline, approveMax, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

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
        // address pair = UniswapV2Library.pairFor(i_factory, token, i_WETH);
        // uint256 value = approveMax ? type(uint256).max : liquidity;
        // IERC20Permit(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        _permitLiquidity(token, i_WETH, liquidity, deadline, approveMax, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                                  SWAP
    //////////////////////////////////////////////////////////////*/
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

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != i_WETH) revert UniswapV2Router__InvalidPath();
        amounts = UniswapV2Library.getAmountsOut(i_factory, amountOut, path);
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
