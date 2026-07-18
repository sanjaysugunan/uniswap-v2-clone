// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";
import {DeployUniswapV2} from "script/DeployUniswapV2.s.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {WETH9} from "../mocks/WETH9.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV2RouterFuzzTest is Test {
    DeployUniswapV2 internal deployer;
    UniswapV2Factory internal factory;
    UniswapV2Router internal router;
    WETH9 internal weth;
    address internal wethAddress;

    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;

    address internal USER = makeAddr("user");

    uint256 internal constant STARTING_BALANCE = 1_000_000 ether;

    function setUp() public {
        deployer = new DeployUniswapV2();
        (factory, router, wethAddress) = deployer.run();
        weth = WETH9(payable(wethAddress));

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        tokenA.mint(USER, STARTING_BALANCE);
        tokenB.mint(USER, STARTING_BALANCE);

        vm.startPrank(USER);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.stopPrank();
    }

    // For recieving ETH
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           ADD LIQUIDITY FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_AddLiquidityReturnsCorrectAmounts(uint256 amountADesired, uint256 amountBDesired) public {
        // Arrange
        (amountADesired, amountBDesired) = _boundLiquidityAmounts(amountADesired, amountBDesired);

        // Act
        (uint256 amountA, uint256 amountB, uint256 liquidity) = _addLiquidity(amountADesired, amountBDesired);

        // Assert
        assertLe(amountA, amountADesired);
        assertLe(amountB, amountBDesired);

        assertGt(amountA, 0);
        assertGt(amountB, 0);
        assertGt(liquidity, 0);
    }

    function testFuzz_AddLiquidityUpdatesPairReserves(uint256 amountADesired, uint256 amountBDesired) public {
        // Arrange
        (amountADesired, amountBDesired) = _boundLiquidityAmounts(amountADesired, amountBDesired);

        _addLiquidity(amountADesired, amountBDesired);

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);

        // Assert
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        assertEq(reserve0, tokenA.balanceOf(pairAddress));
        assertEq(reserve1, tokenB.balanceOf(pairAddress));
    }

    /*//////////////////////////////////////////////////////////////
                         REMOVE LIQUIDITY FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_RemoveLiquidityReturnsAssets(uint256 amountA, uint256 amountB) public {
        // Arrange
        (amountA, amountB) = _boundLiquidityAmounts(amountA, amountB);

        _addLiquidity(amountA, amountB);

        uint256 tokenABalanceBefore = tokenA.balanceOf(USER);
        uint256 tokenBBalanceBefore = tokenB.balanceOf(USER);

        // Act
        (uint256 amountAReturned, uint256 amountBReturned) = _burnLiquidity(USER);

        // Assert
        assertEq(tokenA.balanceOf(USER), tokenABalanceBefore + amountAReturned);
        assertEq(tokenB.balanceOf(USER), tokenBBalanceBefore + amountBReturned);

        assertGt(amountAReturned, 0);
        assertGt(amountBReturned, 0);
    }

    function testFuzz_RemoveLiquidityBurnsLPTokens(uint256 amountA, uint256 amountB) public {
        // Arrange
        (amountA, amountB) = _boundLiquidityAmounts(amountA, amountB);

        _addLiquidity(amountA, amountB);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        uint256 lpBalanceBefore = IERC20(pair).balanceOf(USER);

        // Act
        _burnLiquidity(USER);

        // Assert
        uint256 lpBalanceAfter = IERC20(pair).balanceOf(USER);

        assertEq(lpBalanceAfter, 0);
        assertGt(lpBalanceBefore, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               SWAP FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_SwapExactTokensForTokensTransfersCorrectOutput(
        uint256 liquidityA,
        uint256 liquidityB,
        uint256 amountIn
    ) public {
        // Arrange
        (liquidityA, liquidityB) = _boundLiquidityAmounts(liquidityA, liquidityB);

        _addLiquidity(liquidityA, liquidityB);

        address[] memory path = _path();

        amountIn = bound(amountIn, 1e6, liquidityA / 10);

        uint256[] memory expectedAmounts = _expectedAmountsOut(amountIn, path);
        vm.assume(expectedAmounts[1] > 0);

        uint256 tokenBBalanceBefore = tokenB.balanceOf(USER);

        // Act
        uint256[] memory amounts = _swapExactTokensForTokens(amountIn, 0);

        // Assert
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmounts[1]);

        assertEq(tokenB.balanceOf(USER), tokenBBalanceBefore + expectedAmounts[1]);
    }

    function testFuzz_SwapTokensForExactTokensTransfersExactOutput(
        uint256 liquidityA,
        uint256 liquidityB,
        uint256 amountOut
    ) public {
        // Arrange
        (liquidityA, liquidityB) = _boundLiquidityAmounts(liquidityA, liquidityB);

        _addLiquidity(liquidityA, liquidityB);

        address[] memory path = _path();

        amountOut = bound(amountOut, 1, liquidityB / 10);

        uint256[] memory expectedAmounts = _expectedAmountsIn(amountOut, path);

        vm.assume(expectedAmounts[0] > 0);

        uint256 tokenBBalanceBefore = tokenB.balanceOf(USER);

        // Act
        uint256[] memory amounts = _swapTokensForExactTokens(amountOut, expectedAmounts[0]);

        // Assert
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], amountOut);

        assertEq(tokenB.balanceOf(USER), tokenBBalanceBefore + amountOut);
    }

    function testFuzz_SwapExactETHForTokensTransfersCorrectOutput(
        uint256 tokenLiquidity,
        uint256 ethLiquidity,
        uint256 amountIn
    ) public {
        // Arrange
        (tokenLiquidity, ethLiquidity) = _boundLiquidityAmounts(tokenLiquidity, ethLiquidity);

        _addLiquidityETH(tokenLiquidity, ethLiquidity);

        address[] memory path = _pathETH();

        amountIn = bound(amountIn, 1e6, ethLiquidity / 10);

        uint256[] memory expectedAmounts = _expectedAmountsOut(amountIn, path);

        vm.assume(expectedAmounts[1] > 0);

        uint256 tokenBalanceBefore = tokenA.balanceOf(USER);

        // Act
        uint256[] memory amounts = _swapExactETHForTokens(amountIn, 0);

        // Assert
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmounts[1]);

        assertEq(tokenA.balanceOf(USER), tokenBalanceBefore + expectedAmounts[1]);
    }

    function testFuzz_SwapExactTokensForETHTransfersCorrectOutput(
        uint256 tokenLiquidity,
        uint256 ethLiquidity,
        uint256 amountIn
    ) public {
        // Arrange
        (tokenLiquidity, ethLiquidity) = _boundLiquidityAmounts(tokenLiquidity, ethLiquidity);

        _addLiquidityETH(tokenLiquidity, ethLiquidity);

        address[] memory path = _pathToETH();

        amountIn = bound(amountIn, 1e6, tokenLiquidity / 10);

        uint256[] memory expectedAmounts = _expectedAmountsOut(amountIn, path);

        vm.assume(expectedAmounts[1] > 0);

        uint256 ethBalanceBefore = USER.balance;

        // Act
        uint256[] memory amounts = _swapExactTokensForETH(amountIn, 0);

        // Assert
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmounts[1]);

        assertEq(USER.balance, ethBalanceBefore + expectedAmounts[1]);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function _boundLiquidityAmounts(uint256 amountA, uint256 amountB) internal pure returns (uint256, uint256) {
        amountA = bound(amountA, 1e10, 1_000 ether);
        amountB = bound(amountB, 1e10, 1_000 ether);

        return (amountA, amountB);
    }

    function _addLiquidity(uint256 amountA, uint256 amountB)
        internal
        returns (uint256 amountAAdded, uint256 amountBAdded, uint256 liquidity)
    {
        vm.startPrank(USER);

        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        (amountAAdded, amountBAdded, liquidity) =
            router.addLiquidity(address(tokenA), address(tokenB), amountA, amountB, 0, 0, USER, block.timestamp);

        vm.stopPrank();
    }

    function _addLiquidityETH(uint256 amountToken, uint256 amountETH)
        internal
        returns (uint256 amountTokenAdded, uint256 amountETHAdded, uint256 liquidity)
    {
        vm.deal(USER, amountETH);

        vm.startPrank(USER);

        tokenA.approve(address(router), amountToken);

        (amountTokenAdded, amountETHAdded, liquidity) =
            router.addLiquidityETH{value: amountETH}(address(tokenA), amountToken, 0, 0, USER, block.timestamp);

        vm.stopPrank();
    }

    function _burnLiquidity(address user) internal returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 liquidity = IERC20(pair).balanceOf(user);

        vm.startPrank(user);

        IERC20(pair).approve(address(router), liquidity);

        (amountA, amountB) =
            router.removeLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, user, block.timestamp);

        vm.stopPrank();
    }

    function _path() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
    }

    function _pathETH() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);
    }

    function _pathToETH() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
    }

    function _expectedAmountsOut(uint256 amountIn, address[] memory path) internal view returns (uint256[] memory) {
        return router.getAmountsOut(amountIn, path);
    }

    function _expectedAmountsIn(uint256 amountOut, address[] memory path) internal view returns (uint256[] memory) {
        return router.getAmountsIn(amountOut, path);
    }

    function _swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin)
        internal
        returns (uint256[] memory amounts)
    {
        vm.startPrank(USER);

        tokenA.approve(address(router), amountIn);

        amounts = router.swapExactTokensForTokens(amountIn, amountOutMin, _path(), USER, block.timestamp);

        vm.stopPrank();
    }

    function _swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax)
        internal
        returns (uint256[] memory amounts)
    {
        vm.startPrank(USER);

        tokenA.approve(address(router), amountInMax);

        amounts = router.swapTokensForExactTokens(amountOut, amountInMax, _path(), USER, block.timestamp);

        vm.stopPrank();
    }

    function _swapExactETHForTokens(uint256 amountIn, uint256 amountOutMin)
        internal
        returns (uint256[] memory amounts)
    {
        vm.deal(USER, amountIn);

        vm.prank(USER);

        amounts = router.swapExactETHForTokens{value: amountIn}(amountOutMin, _pathETH(), USER, block.timestamp);
    }

    function _swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin)
        internal
        returns (uint256[] memory amounts)
    {
        vm.startPrank(USER);

        tokenA.approve(address(router), amountIn);

        amounts = router.swapExactTokensForETH(amountIn, amountOutMin, _pathToETH(), USER, block.timestamp);

        vm.stopPrank();
    }
}

