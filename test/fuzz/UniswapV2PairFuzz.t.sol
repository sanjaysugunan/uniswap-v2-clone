// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {UniswapV2Library} from "src/libraries/UniswapV2Library.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract UniswapV2PairFuzzTest is Test {
    UniswapV2Factory internal factory;
    UniswapV2Pair internal pair;

    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;

    address internal USER = makeAddr("user");

    uint256 internal constant STARTING_BALANCE = 1_000_000_000 ether;

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
                               MINT FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_MintUpdatesReserves(uint256 amount0, uint256 amount1) public {
        (amount0, amount1) = _boundLiquidityAmounts(amount0, amount1);
        // Act
        _addLiquidity(amount0, amount1);

        // Assert
        (uint112 reserve0, uint112 reserve1,) = _getReserves();

        assertEq(reserve0, tokenA.balanceOf(address(pair)));
        assertEq(reserve1, tokenB.balanceOf(address(pair)));
    }

    function testFuzz_MintMintsPositiveLiquidity(uint256 amount0, uint256 amount1) public {
        (amount0, amount1) = _boundLiquidityAmounts(amount0, amount1);

        uint256 liquidity = _addLiquidity(amount0, amount1);

        assertGt(liquidity, 0);
        assertGt(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());

        assertEq(pair.balanceOf(USER), pair.totalSupply() - pair.MINIMUM_LIQUIDITY());
    }

    function testFuzz_MintLiquidityMatchesFormula(uint256 amount0, uint256 amount1, uint256 scale) public {
        // Arrange
        (amount0, amount1) = _boundLiquidityAmounts(amount0, amount1);
        scale = bound(scale, 100, 1000);

        _addLiquidity(amount0, amount1);

        (uint112 reserve0, uint112 reserve1,) = _getReserves();
        uint256 totalSupply = pair.totalSupply();

        uint256 amount0Second = reserve0 * scale;
        uint256 amount1Second = reserve1 * scale;

        uint256 expectedLiquidity =
            Math.min(amount0Second * totalSupply / reserve0, amount1Second * totalSupply / reserve1);

        // Act
        uint256 liquidityMinted = _addLiquidity(amount0Second, amount1Second);

        // Assert
        assertEq(liquidityMinted, expectedLiquidity);
    }

    /*//////////////////////////////////////////////////////////////
                               BURN FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_BurnReturnsLiquidityProportionally(uint256 amount0, uint256 amount1) public {
        // Arrange
        (amount0, amount1) = _boundLiquidityAmounts(amount0, amount1);

        uint256 liquidity = _addLiquidity(amount0, amount1);

        uint256 totalSupply = pair.totalSupply();
        uint256 pairBalance0 = tokenA.balanceOf(address(pair));
        uint256 pairBalance1 = tokenB.balanceOf(address(pair));

        uint256 expectedAmount0 = (liquidity * pairBalance0) / totalSupply;
        uint256 expectedAmount1 = (liquidity * pairBalance1) / totalSupply;

        // Act
        (uint256 amount0Returned, uint256 amount1Returned) = _burnLiquidity(USER);

        // Assert
        assertEq(amount0Returned, expectedAmount0);
        assertEq(amount1Returned, expectedAmount1);
    }

    function testFuzz_BurnUpdatesReserves(uint256 amount0, uint256 amount1) public {
        // Arrange
        (amount0, amount1) = _boundLiquidityAmounts(amount0, amount1);

        _addLiquidity(amount0, amount1);

        // Act
        _burnLiquidity(USER);

        // Assert
        (uint112 reserve0, uint112 reserve1,) = _getReserves();

        assertEq(reserve0, tokenA.balanceOf(address(pair)));
        assertEq(reserve1, tokenB.balanceOf(address(pair)));
    }

    /*//////////////////////////////////////////////////////////////
                               SWAP FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_SwapPreservesInvariant(uint256 liquidity, uint256 amountIn) public {
        // Arrange
        liquidity = bound(liquidity, 1 ether, 1000 ether);

        _addLiquidity(liquidity, liquidity);

        (uint112 reserve0Before, uint112 reserve1Before,) = _getReserves();

        amountIn = bound(amountIn, 1e6, reserve0Before / 10);

        uint256 amountOut = UniswapV2Library.getAmountOut(amountIn, reserve0Before, reserve1Before);

        _transferToPair(amountIn, 0);

        // Act
        _swap(0, amountOut, USER);

        // Assert
        uint256 balance0 = tokenA.balanceOf(address(pair));
        uint256 balance1 = tokenB.balanceOf(address(pair));

        uint256 amount0In = balance0 > reserve0Before - 0 ? balance0 - reserve0Before : 0;

        uint256 amount1In = balance1 > reserve1Before - amountOut ? balance1 - (reserve1Before - amountOut) : 0;

        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;

        assertGe(balance0Adjusted * balance1Adjusted, uint256(reserve0Before) * uint256(reserve1Before) * 1000 ** 2);
    }

    function testFuzz_SwapUpdatesReserves(uint256 liquidity, uint256 amountIn) public {
        // Arrange
        liquidity = bound(liquidity, 10 ether, 1_000 ether);

        _addLiquidity(liquidity, liquidity);

        (uint112 reserve0Before, uint112 reserve1Before,) = _getReserves();

        amountIn = bound(amountIn, 1e6, reserve0Before / 10);

        uint256 amountOut = UniswapV2Library.getAmountOut(amountIn, reserve0Before, reserve1Before);

        _transferToPair(amountIn, 0);

        // Act
        _swap(0, amountOut, USER);

        // Assert
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        assertEq(reserve0After, tokenA.balanceOf(address(pair)));
        assertEq(reserve1After, tokenB.balanceOf(address(pair)));
    }

    function testFuzz_SwapTransfersOutputTokens(uint256 liquidity, uint256 amountIn) public {
        // Arrange
        liquidity = bound(liquidity, 10 ether, 1_000 ether);

        _addLiquidity(liquidity, liquidity);

        (uint112 reserve0, uint112 reserve1,) = _getReserves();

        amountIn = bound(amountIn, 1e6, reserve0 / 10);

        uint256 amountOut = UniswapV2Library.getAmountOut(amountIn, reserve0, reserve1);

        uint256 userBalanceBefore = tokenB.balanceOf(USER);

        _transferToPair(amountIn, 0);

        // Act
        _swap(0, amountOut, USER);

        // Assert
        assertEq(tokenB.balanceOf(USER), userBalanceBefore + amountOut);
    }

    /*//////////////////////////////////////////////////////////////
                             SYNC/SKIM FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_SyncUpdatesReserves(uint256 liquidity, uint256 extra0, uint256 extra1) public {
        // Arrange
        liquidity = bound(liquidity, 10 ether, 1_000 ether);
        extra0 = bound(extra0, 1, 100 ether);
        extra1 = bound(extra1, 1, 100 ether);

        _addLiquidity(liquidity, liquidity);

        vm.startPrank(USER);

        tokenA.transfer(address(pair), extra0);
        tokenB.transfer(address(pair), extra1);

        vm.stopPrank();

        // Act
        pair.sync();

        // Assert
        (uint112 reserve0, uint112 reserve1,) = _getReserves();

        assertEq(reserve0, tokenA.balanceOf(address(pair)));
        assertEq(reserve1, tokenB.balanceOf(address(pair)));

        assertEq(reserve0, liquidity + extra0);
        assertEq(reserve1, liquidity + extra1);
    }

    function testFuzz_SkimTransfersExcess(uint256 liquidity, uint256 excess0, uint256 excess1) public {
        // Arrange
        liquidity = bound(liquidity, 10 ether, 1_000 ether);
        excess0 = bound(excess0, 1, 100 ether);
        excess1 = bound(excess1, 1, 100 ether);

        _addLiquidity(liquidity, liquidity);

        _transferToPair(excess0, excess1);

        uint256 tokenABalanceBefore = tokenA.balanceOf(USER);
        uint256 tokenBBalanceBefore = tokenB.balanceOf(USER);

        // Act
        pair.skim(USER);

        // Assert
        assertEq(tokenA.balanceOf(USER), tokenABalanceBefore + excess0);
        assertEq(tokenB.balanceOf(USER), tokenBBalanceBefore + excess1);

        (uint112 reserve0, uint112 reserve1,) = _getReserves();

        // Reserves should remain unchanged
        assertEq(reserve0, liquidity);
        assertEq(reserve1, liquidity);

        // Pair balances should now equal reserves
        assertEq(tokenA.balanceOf(address(pair)), reserve0);
        assertEq(tokenB.balanceOf(address(pair)), reserve1);
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
        _transferToPair(amount0, amount1);

        liquidity = pair.mint(USER);
    }

    function _burnLiquidity(address to) internal returns (uint256 amount0, uint256 amount1) {
        return _burnLiquidity(to, pair.balanceOf(USER));
    }

    function _burnLiquidity(address to, uint256 liquidity) internal returns (uint256 amount0, uint256 amount1) {
        vm.startPrank(USER);

        pair.transfer(address(pair), liquidity);

        (amount0, amount1) = pair.burn(to);

        vm.stopPrank();
    }

    function _getReserves() internal view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return pair.getReserves();
    }

    function _swap(uint256 amount0Out, uint256 amount1Out, address to) internal {
        vm.prank(USER);
        pair.swap(amount0Out, amount1Out, to, "");
    }

    function _transferToPair(uint256 amount0In, uint256 amount1In) internal {
        if (amount0In > 0) {
            vm.prank(USER);
            tokenA.transfer(address(pair), amount0In);
        }

        if (amount1In > 0) {
            vm.prank(USER);
            tokenB.transfer(address(pair), amount1In);
        }
    }
}
