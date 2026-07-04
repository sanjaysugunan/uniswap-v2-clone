// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract UniswapV2PairFuzzTest is Test {
    UniswapV2Factory internal factory;
    UniswapV2Pair internal pair;

    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;

    address internal USER = makeAddr("user");

    uint256 internal constant STARTING_BALANCE = 1_000_000 ether;

    function setUp() public {
        factory = new UniswapV2Factory();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        tokenA.mint(USER, STARTING_BALANCE);
        tokenB.mint(USER, STARTING_BALANCE);

        factory.createPair(address(tokenA), address(tokenB));
        pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        vm.startPrank(USER);

        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _boundLiquidityAmounts(uint256 amount0, uint256 amount1) internal pure returns (uint256, uint256) {
        amount0 = bound(amount0, 1e6, 1_000 ether);
        amount1 = bound(amount1, 1e6, 1_000 ether);

        return (amount0, amount1);
    }

    function _addLiquidity(uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        (amount0, amount1) = _boundLiquidityAmounts(amount0, amount1);

        vm.startPrank(USER);

        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);

        liquidity = pair.mint(USER);

        vm.stopPrank();
    }
}
