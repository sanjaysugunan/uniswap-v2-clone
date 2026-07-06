// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";
import {IUniswapV2Router} from "src/interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "src/libraries/UniswapV2Library.sol";
import {DeployUniswapV2} from "script/DeployUniswapV2.s.sol";
import {WETH9} from "../mocks/WETH9.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract UniswapV2RouterSwapTest is Test {
    DeployUniswapV2 public deployer;
    UniswapV2Factory public factory;
    UniswapV2Router public router;
    WETH9 public weth;
    address public wethAddress;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;

    address USER1 = makeAddr("user1");
    address USER2 = makeAddr("user2");

    /*//////////////////////////////////////////////////////////////
                                USERS
    //////////////////////////////////////////////////////////////*/
    uint256 constant STARTING_USER_BALANCE = 100 ether;

    /*//////////////////////////////////////////////////////////////
                              LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    uint256 constant INITIAL_LIQUIDITY = 10 ether;
    uint256 constant LOCKED_LIQUIDITY = 10 ** 3;

    /*//////////////////////////////////////////////////////////////
                                 SWAPS
    //////////////////////////////////////////////////////////////*/

    uint256 constant SWAP_INPUT = 1 ether;
    uint256 constant SMALL_SWAP_INPUT = 0.1 ether;
    uint256 constant LARGE_SWAP_INPUT = 5 ether;

    uint256 constant MIN_AMOUNT_OUT = 0;
    uint256 constant IMPOSSIBLE_AMOUNT_OUT = type(uint256).max;

    function setUp() public {
        deployer = new DeployUniswapV2();
        (factory, router, wethAddress) = deployer.run();
        weth = WETH9(payable(wethAddress));

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();

        for (uint256 i; i < 2; i++) {
            address user = i == 0 ? USER1 : USER2;

            tokenA.mint(user, STARTING_USER_BALANCE);
            tokenB.mint(user, STARTING_USER_BALANCE);
            tokenC.mint(user, STARTING_USER_BALANCE);
        }
    }

    // for recieving ETH
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                              SWAP HELPERS
    //////////////////////////////////////////////////////////////*/
    function testSwapExactTokensForTokensWorks() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        address[] memory path = _path(tokenA, tokenB);
        uint256[] memory expectedAmounts = _expectedAmountsOut(SWAP_INPUT, path);

        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);

        // Act
        uint256[] memory amounts = _swapExactTokensForTokens(USER2, tokenA, tokenB, SWAP_INPUT);

        // Assert returned amounts
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore - SWAP_INPUT);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore + expectedAmounts[1]);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testSwapExactTokensForTokensWorksMultiHop() public {
        // Arrange
        _seedPool(tokenA, tokenB);
        _seedPool(tokenB, tokenC);

        address[] memory path = _path3(tokenA, tokenB, tokenC);
        uint256[] memory expectedAmounts = _expectedAmountsOut(SWAP_INPUT, path);

        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);
        uint256 userTokenCBalanceBefore = tokenC.balanceOf(USER2);

        // Act
        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        uint256[] memory amounts = router.swapExactTokensForTokens(SWAP_INPUT, 0, path, USER2, block.timestamp);

        vm.stopPrank();

        // Assert returned amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore - SWAP_INPUT);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore);
        assertEq(tokenC.balanceOf(USER2), userTokenCBalanceBefore + expectedAmounts[2]);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(tokenC.balanceOf(address(router)), 0);
    }

    function testSwapExactTokensForTokensRevertsIfDeadlineExpired() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.swapExactTokensForTokens(SWAP_INPUT, 0, _path(tokenA, tokenB), USER2, deadline);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokensRevertsIfInsufficientOutputAmount() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientOutputAmount.selector);
        router.swapExactTokensForTokens(
            SWAP_INPUT, IMPOSSIBLE_AMOUNT_OUT, _path(tokenA, tokenB), USER2, block.timestamp
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                      SWAP TOKENS FOR EXACT TOKENS
    //////////////////////////////////////////////////////////////*/
    function testSwapTokensForExactTokensWorks() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        address[] memory path = _path(tokenA, tokenB);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);

        // Act
        uint256[] memory amounts = _swapTokensForExactTokens(USER2, tokenA, tokenB, SWAP_INPUT, expectedAmounts[0]);

        // Assert returned amounts
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore - expectedAmounts[0]);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore + SWAP_INPUT);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testSwapTokensForExactTokensWorksMultiHop() public {
        // Arrange
        _seedPool(tokenA, tokenB);
        _seedPool(tokenB, tokenC);

        address[] memory path = _path3(tokenA, tokenB, tokenC);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);
        uint256 userTokenCBalanceBefore = tokenC.balanceOf(USER2);

        // Act
        vm.startPrank(USER2);
        tokenA.approve(address(router), expectedAmounts[0]);

        uint256[] memory amounts =
            router.swapTokensForExactTokens(SWAP_INPUT, expectedAmounts[0], path, USER2, block.timestamp);
        vm.stopPrank();

        // Assert returned amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore - expectedAmounts[0]);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore);
        assertEq(tokenC.balanceOf(USER2), userTokenCBalanceBefore + SWAP_INPUT);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(tokenC.balanceOf(address(router)), 0);
    }

    function testSwapTokensForExactTokensRevertsIfDeadlineExpired() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        address[] memory path = _path(tokenA, tokenB);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        vm.startPrank(USER2);
        tokenA.approve(address(router), expectedAmounts[0]);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.swapTokensForExactTokens(SWAP_INPUT, expectedAmounts[0], path, USER2, deadline);

        vm.stopPrank();
    }

    function testSwapTokensForExactTokensRevertsIfExcessiveInputAmount() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        address[] memory path = _path(tokenA, tokenB);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        vm.startPrank(USER2);
        tokenA.approve(address(router), expectedAmounts[0]);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__ExcessiveInputAmount.selector);
        router.swapTokensForExactTokens(SWAP_INPUT, expectedAmounts[0] - 1, path, USER2, block.timestamp);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       SWAP EXACT ETH FOR TOKENS
    //////////////////////////////////////////////////////////////*/
    function testSwapExactETHForTokensWorks() public {
        // Arrange
        _seedPoolETH(tokenA);

        address[] memory path = _pathETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsOut(SWAP_INPUT, path);

        vm.deal(USER2, STARTING_USER_BALANCE);

        uint256 userEthBalanceBefore = USER2.balance;
        uint256 userTokenBalanceBefore = tokenA.balanceOf(USER2);

        // Act
        uint256[] memory amounts = _swapExactETHForTokens(USER2, tokenA, SWAP_INPUT);

        // Assert returned amounts
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);

        // Assert user balances
        console2.log(USER2.balance);
        console2.log(userEthBalanceBefore);
        assertEq(USER2.balance, userEthBalanceBefore - SWAP_INPUT);
        assertEq(tokenA.balanceOf(USER2), userTokenBalanceBefore + expectedAmounts[1]);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
    }

    function testSwapExactETHForTokensWorksMultiHop() public {
        // Arrange
        _seedPoolETH(tokenA);
        _seedPool(tokenA, tokenB);

        vm.deal(USER2, STARTING_USER_BALANCE);

        address[] memory path = _path3(ERC20Mock(address(weth)), tokenA, tokenB);
        uint256[] memory expectedAmounts = _expectedAmountsOut(SWAP_INPUT, path);

        uint256 userEthBalanceBefore = USER2.balance;
        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);

        // Act
        vm.prank(USER2);
        uint256[] memory amounts = router.swapExactETHForTokens{value: SWAP_INPUT}(0, path, USER2, block.timestamp);

        // Assert returned amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        // Assert user balances
        assertEq(USER2.balance, userEthBalanceBefore - SWAP_INPUT);
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore + expectedAmounts[2]);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testSwapExactETHForTokensRevertsIfDeadlineExpired() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.deal(USER2, STARTING_USER_BALANCE);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.prank(USER2);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.swapExactETHForTokens{value: SWAP_INPUT}(0, _pathETH(tokenA), USER2, deadline);
    }

    function testSwapExactETHForTokensRevertsIfInvalidPath() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.deal(USER2, STARTING_USER_BALANCE);

        address[] memory invalidPath = new address[](2);
        invalidPath[0] = address(tokenA);
        invalidPath[1] = address(tokenB);

        // Act
        vm.prank(USER2);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InvalidPath.selector);
        router.swapExactETHForTokens{value: SWAP_INPUT}(0, invalidPath, USER2, block.timestamp);
    }

    function testSwapExactETHForTokensRevertsIfInsufficientOutputAmount() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.deal(USER2, STARTING_USER_BALANCE);

        // Act
        vm.prank(USER2);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientOutputAmount.selector);
        router.swapExactETHForTokens{value: SWAP_INPUT}(IMPOSSIBLE_AMOUNT_OUT, _pathETH(tokenA), USER2, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                       SWAP TOKENS FOR EXACT ETH
    //////////////////////////////////////////////////////////////*/
    function testSwapTokensForExactETHWorks() public {
        // Arrange
        _seedPoolETH(tokenA);

        address[] memory path = _pathToETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 userTokenBalanceBefore = tokenA.balanceOf(USER2);
        uint256 userEthBalanceBefore = USER2.balance;

        // Act
        uint256[] memory amounts = _swapTokensForExactETH(USER2, tokenA, SWAP_INPUT, expectedAmounts[0]);

        // Assert returned amounts
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenBalanceBefore - expectedAmounts[0]);
        assertEq(USER2.balance, userEthBalanceBefore + SWAP_INPUT);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
    }

    function testSwapTokensForExactETHWorksMultiHop() public {
        // Arrange
        _seedPool(tokenA, tokenB);
        _seedPoolETH(tokenB);

        address[] memory path = _path3(tokenA, tokenB, ERC20Mock(address(weth)));
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);
        uint256 userEthBalanceBefore = USER2.balance;

        // Act
        vm.startPrank(USER2);
        tokenA.approve(address(router), expectedAmounts[0]);

        uint256[] memory amounts =
            router.swapTokensForExactETH(SWAP_INPUT, expectedAmounts[0], path, USER2, block.timestamp);

        vm.stopPrank();

        // Assert returned amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore - expectedAmounts[0]);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore);
        assertEq(USER2.balance, userEthBalanceBefore + SWAP_INPUT);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testSwapTokensForExactETHRevertsIfDeadlineExpired() public {
        // Arrange
        _seedPoolETH(tokenA);

        address[] memory path = _pathToETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        vm.startPrank(USER2);
        tokenA.approve(address(router), expectedAmounts[0]);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.swapTokensForExactETH(SWAP_INPUT, expectedAmounts[0], path, USER2, deadline);

        vm.stopPrank();
    }

    function testSwapTokensForExactETHRevertsIfInvalidPath() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), STARTING_USER_BALANCE);

        address[] memory invalidPath = _path(tokenA, tokenB);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InvalidPath.selector);
        router.swapTokensForExactETH(SWAP_INPUT, STARTING_USER_BALANCE, invalidPath, USER2, block.timestamp);

        vm.stopPrank();
    }

    function testSwapTokensForExactETHRevertsIfExcessiveInputAmount() public {
        // Arrange
        _seedPoolETH(tokenA);

        address[] memory path = _pathToETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        vm.startPrank(USER2);
        tokenA.approve(address(router), expectedAmounts[0]);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__ExcessiveInputAmount.selector);
        router.swapTokensForExactETH(SWAP_INPUT, expectedAmounts[0] - 1, path, USER2, block.timestamp);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       SWAP EXACT TOKENS FOR ETH
    //////////////////////////////////////////////////////////////*/
    function testSwapExactTokensForETHWorks() public {
        // Arrange
        _seedPoolETH(tokenA);

        address[] memory path = _pathToETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsOut(SWAP_INPUT, path);

        uint256 userTokenBalanceBefore = tokenA.balanceOf(USER2);
        uint256 userEthBalanceBefore = USER2.balance;

        // Act
        uint256[] memory amounts = _swapExactTokensForETH(USER2, tokenA, SWAP_INPUT);

        // Assert returned amounts
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenBalanceBefore - SWAP_INPUT);
        assertEq(USER2.balance, userEthBalanceBefore + expectedAmounts[1]);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
    }

    function testSwapExactTokensForETHWorksMultiHop() public {
        // Arrange
        _seedPool(tokenA, tokenB);
        _seedPoolETH(tokenB);

        address[] memory path = _path3(tokenA, tokenB, ERC20Mock(address(weth)));
        uint256[] memory expectedAmounts = _expectedAmountsOut(SWAP_INPUT, path);

        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);
        uint256 userEthBalanceBefore = USER2.balance;

        // Act
        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        uint256[] memory amounts = router.swapExactTokensForETH(SWAP_INPUT, 0, path, USER2, block.timestamp);

        vm.stopPrank();

        // Assert returned amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        // Assert user balances
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore - SWAP_INPUT);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore);
        assertEq(USER2.balance, userEthBalanceBefore + expectedAmounts[2]);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testSwapExactTokensForETHRevertsIfDeadlineExpired() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.swapExactTokensForETH(SWAP_INPUT, 0, _pathToETH(tokenA), USER2, deadline);

        vm.stopPrank();
    }

    function testSwapExactTokensForETHRevertsIfInvalidPath() public {
        // Arrange
        _seedPool(tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        address[] memory invalidPath = _path(tokenA, tokenB);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InvalidPath.selector);
        router.swapExactTokensForETH(SWAP_INPUT, 0, invalidPath, USER2, block.timestamp);

        vm.stopPrank();
    }

    function testSwapExactTokensForETHRevertsIfInsufficientOutputAmount() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.startPrank(USER2);
        tokenA.approve(address(router), SWAP_INPUT);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientOutputAmount.selector);
        router.swapExactTokensForETH(SWAP_INPUT, IMPOSSIBLE_AMOUNT_OUT, _pathToETH(tokenA), USER2, block.timestamp);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       SWAP ETH FOR EXACT TOKENS
    //////////////////////////////////////////////////////////////*/
    function testSwapETHForExactTokensWorks() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.deal(USER2, STARTING_USER_BALANCE);

        address[] memory path = _pathETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 userEthBalanceBefore = USER2.balance;
        uint256 userTokenBalanceBefore = tokenA.balanceOf(USER2);

        // Act
        uint256[] memory amounts = _swapETHForExactTokens(USER2, tokenA, SWAP_INPUT, expectedAmounts[0]);

        // Assert returned amounts
        assertEq(amounts.length, 2);

        assertEq(amounts[0], expectedAmounts[0]);
        console2.log("reached");

        assertEq(amounts[1], expectedAmounts[1]);

        // Assert user balances
        assertEq(USER2.balance, userEthBalanceBefore - expectedAmounts[0]);
        assertEq(tokenA.balanceOf(USER2), userTokenBalanceBefore + SWAP_INPUT);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
    }

    function testSwapETHForExactTokensWorksMultiHop() public {
        // Arrange
        _seedPoolETH(tokenA);
        _seedPool(tokenA, tokenB);

        vm.deal(USER2, STARTING_USER_BALANCE);

        address[] memory path = _path3(ERC20Mock(address(weth)), tokenA, tokenB);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 userEthBalanceBefore = USER2.balance;
        uint256 userTokenABalanceBefore = tokenA.balanceOf(USER2);
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(USER2);

        // Act
        vm.prank(USER2);
        uint256[] memory amounts =
            router.swapETHForExactTokens{value: expectedAmounts[0]}(SWAP_INPUT, path, USER2, block.timestamp);

        // Assert returned amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        // Assert user balances
        assertEq(USER2.balance, userEthBalanceBefore - expectedAmounts[0]);
        assertEq(tokenA.balanceOf(USER2), userTokenABalanceBefore);
        assertEq(tokenB.balanceOf(USER2), userTokenBBalanceBefore + SWAP_INPUT);

        // Router should never retain assets
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testSwapETHForExactTokensRefundsExcessETH() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.deal(USER2, STARTING_USER_BALANCE);

        address[] memory path = _pathETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        uint256 excessETH = 1 ether;
        uint256 msgValue = expectedAmounts[0] + excessETH;

        uint256 userEthBalanceBefore = USER2.balance;

        // Act
        uint256[] memory amounts = _swapETHForExactTokens(USER2, tokenA, SWAP_INPUT, msgValue);

        // Assert returned amounts
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);

        // User should only pay the required ETH, not msg.value
        assertEq(USER2.balance, userEthBalanceBefore - expectedAmounts[0]);

        // Router should retain nothing
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(tokenA.balanceOf(address(router)), 0);
    }

    function testSwapETHForExactTokensRevertsIfDeadlineExpired() public {
        // Arrange
        _seedPoolETH(tokenA);

        vm.deal(USER2, STARTING_USER_BALANCE);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.prank(USER2);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.swapETHForExactTokens{value: SWAP_INPUT}(SWAP_INPUT, _pathETH(tokenA), USER2, deadline);
    }

    function testSwapETHForExactTokensRevertsIfInvalidPath() public {
        // Arrange
        vm.deal(USER2, STARTING_USER_BALANCE);

        address[] memory invalidPath = _path(tokenA, tokenB);

        // Act
        vm.prank(USER2);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InvalidPath.selector);
        router.swapETHForExactTokens{value: SWAP_INPUT}(SWAP_INPUT, invalidPath, USER2, block.timestamp);
    }

    function testSwapETHForExactTokensRevertsIfExcessiveInputAmount() public {
        // Arrange
        _seedPoolETH(tokenA);

        address[] memory path = _pathETH(tokenA);
        uint256[] memory expectedAmounts = _expectedAmountsIn(SWAP_INPUT, path);

        vm.deal(USER2, STARTING_USER_BALANCE);

        // Act
        vm.prank(USER2);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__ExcessiveInputAmount.selector);
        router.swapETHForExactTokens{value: expectedAmounts[0] - 1}(SWAP_INPUT, path, USER2, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                RECIEVE
    //////////////////////////////////////////////////////////////*/
    function testReceiveRevertsIfSenderIsNotWETH() public {
        vm.deal(USER1, 1 ether);

        vm.prank(USER1);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__OnlyWETH.selector);

        (bool success,) = address(router).call{value: 1 ether}("");

        success;
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS TEST
    //////////////////////////////////////////////////////////////*/
    function testFactoryReturnsFactoryAddress() public view {
        assertEq(router.factory(), address(factory));
    }

    function testWETHReturnsWETHAddress() public view {
        assertEq(router.WETH(), address(weth));
    }

    function testQuoteReturnsCorrectValue() public view {
        uint256 amountB = router.quote(1 ether, 10 ether, 20 ether);

        assertEq(amountB, 2 ether);
    }

    function testGetAmountOutReturnsCorrectValue() public view {
        uint256 amountOut = router.getAmountOut(SWAP_INPUT, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 expected = UniswapV2Library.getAmountOut(SWAP_INPUT, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        assertEq(amountOut, expected);
    }

    function testGetAmountInReturnsCorrectValue() public view {
        uint256 amountIn = router.getAmountIn(SWAP_INPUT, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 expected = UniswapV2Library.getAmountIn(SWAP_INPUT, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        assertEq(amountIn, expected);
    }

    function testGetAmountsOutReturnsCorrectValuesMultiHop() public {
        _seedPool(tokenA, tokenB);
        _seedPool(tokenB, tokenC);

        address[] memory path = _path3(tokenA, tokenB, tokenC);

        uint256[] memory amounts = router.getAmountsOut(SWAP_INPUT, path);
        uint256[] memory expected = _expectedAmountsOut(SWAP_INPUT, path);

        assertEq(amounts.length, 3);
        assertEq(amounts[0], expected[0]);
        assertEq(amounts[1], expected[1]);
        assertEq(amounts[2], expected[2]);
    }

    function testGetAmountsInReturnsCorrectValues() public {
        _seedPool(tokenA, tokenB);

        address[] memory path = _path(tokenA, tokenB);

        uint256[] memory amounts = router.getAmountsIn(SWAP_INPUT, path);
        uint256[] memory expected = _expectedAmountsIn(SWAP_INPUT, path);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], expected[0]);
        assertEq(amounts[1], expected[1]);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    /*/---------------Add Liquidity Helpers----------------------/*/
    function _addLiquidity(address user, ERC20Mock token0, ERC20Mock token1)
        internal
        returns (address pair, uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        vm.startPrank(user);

        token0.approve(address(router), INITIAL_LIQUIDITY);
        token1.approve(address(router), INITIAL_LIQUIDITY);

        (amount0, amount1, liquidity) = router.addLiquidity(
            address(token0), address(token1), INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0, 0, user, block.timestamp
        );

        vm.stopPrank();

        pair = factory.getPair(address(token0), address(token1));
    }

    function _addLiquidityETH(address user, ERC20Mock token)
        internal
        returns (address pair, uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        vm.deal(user, STARTING_USER_BALANCE);

        vm.startPrank(user);

        token.approve(address(router), INITIAL_LIQUIDITY);

        (amountToken, amountETH, liquidity) = router.addLiquidityETH{value: INITIAL_LIQUIDITY}(
            address(token), INITIAL_LIQUIDITY, 0, 0, user, block.timestamp
        );

        vm.stopPrank();

        pair = factory.getPair(address(token), address(weth));
    }

    function _seedPool(ERC20Mock token0, ERC20Mock token1) internal returns (UniswapV2Pair pair) {
        (address pairAddress,,,) = _addLiquidity(USER1, token0, token1);

        pair = UniswapV2Pair(pairAddress);
    }

    function _seedPoolETH(ERC20Mock token) internal returns (UniswapV2Pair pair) {
        (address pairAddress,,,) = _addLiquidityETH(USER1, token);

        pair = UniswapV2Pair(pairAddress);
    }

    /*/-----------------------Swap Helpers----------------------/*/
    function _swapExactTokensForTokens(address user, ERC20Mock tokenIn, ERC20Mock tokenOut, uint256 amountIn)
        internal
        returns (uint256[] memory amounts)
    {
        vm.startPrank(user);

        tokenIn.approve(address(router), amountIn);

        amounts = router.swapExactTokensForTokens(amountIn, 0, _path(tokenIn, tokenOut), user, block.timestamp);

        vm.stopPrank();
    }

    function _swapTokensForExactTokens(
        address user,
        ERC20Mock tokenIn,
        ERC20Mock tokenOut,
        uint256 amountOut,
        uint256 amountInMax
    ) internal returns (uint256[] memory amounts) {
        vm.startPrank(user);

        tokenIn.approve(address(router), amountInMax);

        amounts =
            router.swapTokensForExactTokens(amountOut, amountInMax, _path(tokenIn, tokenOut), user, block.timestamp);

        vm.stopPrank();
    }

    function _swapExactETHForTokens(address user, ERC20Mock tokenOut, uint256 amountIn)
        internal
        returns (uint256[] memory amounts)
    {
        vm.prank(user);

        amounts = router.swapExactETHForTokens{value: amountIn}(0, _pathETH(tokenOut), user, block.timestamp);
    }

    function _swapTokensForExactETH(address user, ERC20Mock tokenIn, uint256 amountOut, uint256 amountInMax)
        internal
        returns (uint256[] memory amounts)
    {
        vm.startPrank(user);

        tokenIn.approve(address(router), amountInMax);

        amounts = router.swapTokensForExactETH(amountOut, amountInMax, _pathToETH(tokenIn), user, block.timestamp);

        vm.stopPrank();
    }

    function _swapExactTokensForETH(address user, ERC20Mock tokenIn, uint256 amountIn)
        internal
        returns (uint256[] memory amounts)
    {
        vm.startPrank(user);

        tokenIn.approve(address(router), amountIn);

        amounts = router.swapExactTokensForETH(amountIn, 0, _pathToETH(tokenIn), user, block.timestamp);

        vm.stopPrank();
    }

    function _swapETHForExactTokens(address user, ERC20Mock tokenOut, uint256 amountOut, uint256 amountInMax)
        internal
        returns (uint256[] memory amounts)
    {
        vm.prank(user);

        amounts = router.swapETHForExactTokens{value: amountInMax}(amountOut, _pathETH(tokenOut), user, block.timestamp);
    }

    /*/-----------------------Path Helpers----------------------/*/
    function _path(ERC20Mock tokenIn, ERC20Mock tokenOut) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);
    }

    function _path3(ERC20Mock tokenIn, ERC20Mock tokenMiddle, ERC20Mock tokenOut)
        internal
        pure
        returns (address[] memory path)
    {
        path = new address[](3);
        path[0] = address(tokenIn);
        path[1] = address(tokenMiddle);
        path[2] = address(tokenOut);
    }

    function _pathETH(ERC20Mock tokenOut) internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenOut);
    }

    function _pathToETH(ERC20Mock tokenIn) internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(weth);
    }

    /*/-----------------------Expected Amounts Helpers----------------------/*/
    function _expectedAmountsOut(uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = UniswapV2Library.getAmountsOut(address(factory), amountIn, path);
    }

    function _expectedAmountsIn(uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = UniswapV2Library.getAmountsIn(address(factory), amountOut, path);
    }
}

