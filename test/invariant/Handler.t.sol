// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";
import {WETH9} from "../mocks/WETH9.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Handler is Test {
    UniswapV2Factory public factory;
    UniswapV2Pair public pair;
    UniswapV2Router public router;
    WETH9 public weth;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    address public USER = makeAddr("user");

    constructor(
        UniswapV2Factory _factory,
        UniswapV2Pair _pair,
        UniswapV2Router _router,
        WETH9 _weth,
        ERC20Mock _tokenA,
        ERC20Mock _tokenB
    ) {
        factory = _factory;
        pair = _pair;
        router = _router;
        weth = _weth;

        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function addLiquidity(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1e6, 1_000 ether);
        amountB = bound(amountB, 1e6, 1_000 ether);

        tokenA.mint(USER, amountA);
        tokenB.mint(USER, amountB);

        vm.startPrank(USER);

        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        router.addLiquidity(address(tokenA), address(tokenB), amountA, amountB, 0, 0, USER, block.timestamp);

        vm.stopPrank();
    }

    function removeLiquidity() public {
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));

        uint256 liquidity = IERC20(pairAddress).balanceOf(USER);

        if (liquidity == 0) return;

        vm.startPrank(USER);

        IERC20(pairAddress).approve(address(router), liquidity);

        router.removeLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, USER, block.timestamp);

        vm.stopPrank();
    }

    function swapExactTokensForTokens(uint256 amountIn) public {
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        if (pairAddress == address(0)) return;

        (uint112 reserveA, uint112 reserveB,) = UniswapV2Pair(pairAddress).getReserves();
        if (reserveA == 0 || reserveB == 0) return;

        amountIn = bound(amountIn, 1e6, reserveA / 10);

        tokenA.mint(USER, amountIn);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        // Ignore swaps that would round down to zero output.
        if (amounts[1] == 0) return;

        vm.startPrank(USER);

        tokenA.approve(address(router), amountIn);

        router.swapExactTokensForTokens(amountIn, 0, path, USER, block.timestamp);

        vm.stopPrank();
    }
}
