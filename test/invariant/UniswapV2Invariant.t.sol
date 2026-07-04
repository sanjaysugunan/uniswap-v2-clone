// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {Handler} from "./Handler.t.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {WETH9} from "../mocks/WETH9.sol";

contract UniswapV2InvariantTest is StdInvariant, Test {
    UniswapV2Factory factory;
    UniswapV2Pair pair;
    UniswapV2Router router;
    WETH9 weth;

    ERC20Mock tokenA;
    ERC20Mock tokenB;

    Handler handler;

    function setUp() public {
        factory = new UniswapV2Factory();

        weth = new WETH9();

        router = new UniswapV2Router(address(factory), address(weth));

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA), address(tokenB), 1000 ether, 1000 ether, 0, 0, address(this), block.timestamp
        );

        pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        handler = new Handler(factory, pair, router, weth, tokenA, tokenB);

        targetContract(address(handler));
    }

    function invariant_ReservesMatchBalances() public view {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        assertEq(reserve0, tokenA.balanceOf(address(pair)));
        assertEq(reserve1, tokenB.balanceOf(address(pair)));
    }

    function invariant_RouterNeverHoldsAssets() public view {
        assertEq(address(router).balance, 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
    }

    function invariant_PairTokensNeverChange() public view {
        (address expectedToken0, address expectedToken1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        assertEq(pair.token0(), expectedToken0);
        assertEq(pair.token1(), expectedToken1);
    }
}
