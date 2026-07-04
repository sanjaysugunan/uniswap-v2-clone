// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2Factory.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract UniswapV2FactoryFuzzTest is Test {
    UniswapV2Factory internal factory;

    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;
    ERC20Mock internal tokenC;

    function setUp() public {
        factory = new UniswapV2Factory();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
    }

    function testFuzz_CreatePair(bool reverseOrder) public {
        address token0 = reverseOrder ? address(tokenB) : address(tokenA);
        address token1 = reverseOrder ? address(tokenA) : address(tokenB);

        address pair = factory.createPair(token0, token1);

        assertEq(factory.getPair(token0, token1), pair);
    }

    function testFuzz_CreatePairIncrementsAllPairsLength(address token0, address token1) public {
        vm.assume(token0 != token1);
        vm.assume(token0 != address(0));
        vm.assume(token1 != address(0));

        uint256 initialLength = factory.allPairsLength();

        factory.createPair(token0, token1);

        assertEq(factory.allPairsLength(), initialLength + 1);
    }

    function testFuzz_CreatePairStoresPair(address token0, address token1) public {
        vm.assume(token0 != token1);
        vm.assume(token0 != address(0));
        vm.assume(token1 != address(0));

        address pair = factory.createPair(token0, token1);

        uint256 index = factory.allPairsLength() - 1;

        assertEq(factory.allPairs(index), pair);
    }

    function testFuzz_CreatePairInitializesPair(address token0, address token1) public {
        vm.assume(token0 != token1);
        vm.assume(token0 != address(0));
        vm.assume(token1 != address(0));

        address pairAddress = factory.createPair(token0, token1);
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);

        (address expectedToken0, address expectedToken1) = token0 < token1 ? (token0, token1) : (token1, token0);

        assertEq(pair.token0(), expectedToken0);
        assertEq(pair.token1(), expectedToken1);
    }

    function testFuzz_CreatePairRevertsIfPairAlreadyExists(address token0, address token1) public {
        vm.assume(token0 != token1);
        vm.assume(token0 != address(0));
        vm.assume(token1 != address(0));

        factory.createPair(token0, token1);

        vm.expectRevert(IUniswapV2Factory.UniswapV2Factory__PairExists.selector);
        factory.createPair(token1, token0);
    }
}
