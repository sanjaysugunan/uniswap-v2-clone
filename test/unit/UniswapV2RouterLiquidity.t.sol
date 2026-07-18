// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";
import {IUniswapV2Router} from "src/interfaces/IUniswapV2Router.sol";
import {DeployUniswapV2} from "script/DeployUniswapV2.s.sol";
import {WETH9} from "../mocks/WETH9.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract UniswapV2RouterLiquidityTest is Test {
    DeployUniswapV2 public deployer;
    UniswapV2Factory public factory;
    UniswapV2Router public router;
    WETH9 public weth;
    address public wethAddress;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    // address USER1;
    // uint256 USER1_PRIVATE_KEY;

    // address USER2;
    // uint256 USER2_PRIVATE_KEY;
    uint256 USER1_PRIVATE_KEY = 1115555551;
    address USER1 = vm.addr(USER1_PRIVATE_KEY);

    uint256 USER2_PRIVATE_KEY = 1115555552;
    address USER2 = vm.addr(USER2_PRIVATE_KEY);

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD; // to lock token since address(0) throws error in oz's ERC20
    // for permit and signing
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                USERS
    //////////////////////////////////////////////////////////////*/
    uint256 constant STARTING_USER_BALANCE = 100 ether;

    uint256 constant LOCKED_LIQUIDITY = 10 ** 3; // UniswapV2Pair.MINIMUM_LIQUIDITY()

    /*//////////////////////////////////////////////////////////////
                         ROUTER CONSTRAINTS
    //////////////////////////////////////////////////////////////*/
    uint256 constant AMOUNT_DESIRED = 10 ether;
    uint256 constant SMALL_AMOUNT_DESIRED = 1 ether;
    uint256 constant LARGE_AMOUNT_DESIRED = 20 ether;

    uint256 constant AMOUNT_MIN = 1 ether;
    uint256 constant STRICT_AMOUNT_MIN = 10 ether;
    uint256 constant IMPOSSIBLE_AMOUNT_MIN = 11 ether;

    function setUp() public {
        // (USER1, USER1_PRIVATE_KEY) = makeAddrAndKey("user1");
        // (USER2, USER2_PRIVATE_KEY) = makeAddrAndKey("user2");

        deployer = new DeployUniswapV2();
        (factory, router, wethAddress) = deployer.run();
        weth = WETH9(payable(wethAddress));

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        for (uint256 i; i < 2; i++) {
            address user = i == 0 ? USER1 : USER2;

            tokenA.mint(user, STARTING_USER_BALANCE);
            tokenB.mint(user, STARTING_USER_BALANCE);
        }
    }

    // for recieving ETH
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                             ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/
    function testAddLiquidityCreatesPair() public {
        (address pair, uint256 amountA, uint256 amountB, uint256 liquidity) = _addLiquidity(USER1, tokenA, tokenB);

        _assertReserves(pair, AMOUNT_DESIRED, AMOUNT_DESIRED);
        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(amountA, AMOUNT_DESIRED);
        assertEq(amountB, AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(UniswapV2Pair(pair).totalSupply(), AMOUNT_DESIRED);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(UniswapV2Pair(pair).balanceOf(BURN_ADDRESS), LOCKED_LIQUIDITY);
    }

    function testAddLiquidityRevertsIfInsufficientAmountB() public {
        _addLiquidity(USER1, tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), AMOUNT_DESIRED);
        tokenB.approve(address(router), AMOUNT_DESIRED);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountA.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            AMOUNT_DESIRED,
            SMALL_AMOUNT_DESIRED,
            IMPOSSIBLE_AMOUNT_MIN,
            STRICT_AMOUNT_MIN,
            USER2,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testAddLiquidityRevertsIfInsufficientAmountA() public {
        _addLiquidity(USER1, tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), AMOUNT_DESIRED);
        tokenB.approve(address(router), AMOUNT_DESIRED);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountB.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            AMOUNT_DESIRED,
            AMOUNT_DESIRED,
            STRICT_AMOUNT_MIN,
            IMPOSSIBLE_AMOUNT_MIN,
            USER2,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testAddLiquidityUsesExistingPair() public {
        _addLiquidity(USER1, tokenA, tokenB);

        // Second liquidity
        (address pair, uint256 amountA, uint256 amountB, uint256 liquidity) = _addLiquidity(USER2, tokenA, tokenB);

        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(amountA, AMOUNT_DESIRED);
        assertEq(amountB, AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED);
        assertEq(tokenA.balanceOf(USER2), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(tokenB.balanceOf(USER2), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(UniswapV2Pair(pair).balanceOf(USER2), AMOUNT_DESIRED);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
    }

    function testAddLiquidityRevertsIfDeadlineExpired() public {
        uint256 lastBlockTimeStamp = block.timestamp;

        vm.warp(lastBlockTimeStamp + 100);
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            AMOUNT_DESIRED,
            AMOUNT_DESIRED,
            STRICT_AMOUNT_MIN,
            STRICT_AMOUNT_MIN,
            USER1,
            lastBlockTimeStamp
        );
    }

    function testAddLiquidityWorksWithUnsortedTokens() public {
        (address pair,,,) = _addLiquidity(USER1, tokenB, tokenA);

        _assertReserves(pair, AMOUNT_DESIRED, AMOUNT_DESIRED);
        assertEq(UniswapV2Pair(pair).token0(), address(tokenA));
        assertEq(UniswapV2Pair(pair).token1(), address(tokenB));
        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
    }

    function testAddLiquidityUsesOptimalAmountB() public {
        _addLiquidity(USER1, tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), AMOUNT_DESIRED);
        tokenB.approve(address(router), LARGE_AMOUNT_DESIRED);

        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            AMOUNT_DESIRED,
            LARGE_AMOUNT_DESIRED,
            AMOUNT_MIN,
            AMOUNT_MIN,
            USER2,
            block.timestamp
        );

        vm.stopPrank();

        UniswapV2Pair pair = _getPair(tokenA, tokenB);

        assertEq(tokenA.balanceOf(USER2), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(tokenB.balanceOf(USER2), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(pair.balanceOf(USER2), AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED);
    }

    function testAddLiquidityUsesOptimalAmountA() public {
        _addLiquidity(USER1, tokenA, tokenB);

        vm.startPrank(USER2);
        tokenA.approve(address(router), LARGE_AMOUNT_DESIRED);
        tokenB.approve(address(router), AMOUNT_DESIRED);

        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LARGE_AMOUNT_DESIRED,
            AMOUNT_DESIRED,
            AMOUNT_MIN,
            AMOUNT_MIN,
            USER2,
            block.timestamp
        );

        vm.stopPrank();

        UniswapV2Pair pair = _getPair(tokenA, tokenB);

        assertEq(tokenA.balanceOf(USER2), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(tokenB.balanceOf(USER2), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(pair.balanceOf(USER2), AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED);
    }

    function testAddLiquidityDoesNotCreateDuplicatePair() public {
        _addLiquidity(USER1, tokenA, tokenB);

        uint256 pairsBefore = factory.allPairsLength();

        _addLiquidity(USER2, tokenA, tokenB);

        assertEq(factory.allPairsLength(), pairsBefore);
    }

    /*//////////////////////////////////////////////////////////////
                           ADD LIQUIDITY ETH
    //////////////////////////////////////////////////////////////*/
    function testAddLiquidityETHCreatesPair() public {
        (address pair, uint256 amountToken, uint256 amountETH, uint256 liquidity) = _addLiquidityETH(USER1, tokenA);

        // Pair
        assertEq(factory.getPair(address(tokenA), address(weth)), pair);

        // Return values
        assertEq(amountToken, AMOUNT_DESIRED);
        assertEq(amountETH, AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // User balances
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - AMOUNT_DESIRED);
        assertEq(address(USER1).balance, 0);

        // Pair balances
        assertEq(tokenA.balanceOf(pair), AMOUNT_DESIRED);
        assertEq(weth.balanceOf(pair), AMOUNT_DESIRED);

        // LP tokens
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // Reserves
        _assertReserves(pair, AMOUNT_DESIRED, AMOUNT_DESIRED);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function testAddLiquidityETHReturnsOptimalAmounts() public {
        _addLiquidityETH(USER1, tokenA);

        vm.deal(USER2, LARGE_AMOUNT_DESIRED);

        vm.startPrank(USER2);
        tokenA.approve(address(router), AMOUNT_DESIRED);

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{
            value: LARGE_AMOUNT_DESIRED
        }(
            address(tokenA), AMOUNT_DESIRED, AMOUNT_MIN, AMOUNT_MIN, USER2, block.timestamp
        );

        vm.stopPrank();

        assertEq(amountToken, AMOUNT_DESIRED);
        assertEq(amountETH, AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED);
        // returns excess ETH to user
        assertEq(address(USER2).balance, LARGE_AMOUNT_DESIRED - AMOUNT_DESIRED);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function testAddLiquidityETHUsesExistingPair() public {
        // First liquidity creates the pair
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 pairCountBefore = factory.allPairsLength();

        // Second liquidity should reuse the existing pair
        vm.deal(USER2, AMOUNT_DESIRED);

        vm.startPrank(USER2);
        tokenA.approve(address(router), AMOUNT_DESIRED);

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{value: AMOUNT_DESIRED}(
            address(tokenA), AMOUNT_DESIRED, STRICT_AMOUNT_MIN, STRICT_AMOUNT_MIN, USER2, block.timestamp
        );
        vm.stopPrank();

        // Pair was reused
        assertEq(factory.getPair(address(tokenA), address(weth)), pair);
        assertEq(factory.allPairsLength(), pairCountBefore);

        // Correct values returned
        assertEq(amountToken, AMOUNT_DESIRED);
        assertEq(amountETH, AMOUNT_DESIRED);
        assertEq(liquidity, AMOUNT_DESIRED);

        // LP tokens minted
        assertEq(UniswapV2Pair(pair).balanceOf(USER2), AMOUNT_DESIRED);

        // Reserves doubled
        _assertReserves(pair, 2 * AMOUNT_DESIRED, 2 * AMOUNT_DESIRED);
    }

    function testAddLiquidityETHRevertsIfDeadlineExpired() public {
        vm.deal(USER1, AMOUNT_DESIRED);

        uint256 deadline = block.timestamp;

        vm.warp(deadline + 1);

        vm.startPrank(USER1);
        tokenA.approve(address(router), AMOUNT_DESIRED);

        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.addLiquidityETH{value: AMOUNT_DESIRED}(
            address(tokenA), AMOUNT_DESIRED, STRICT_AMOUNT_MIN, STRICT_AMOUNT_MIN, USER1, deadline
        );

        vm.stopPrank();
    }

    function testAddLiquidityETHRevertsIfInsufficientTokenAmount() public {
        _addLiquidityETH(USER1, tokenA);

        vm.deal(USER2, SMALL_AMOUNT_DESIRED);

        vm.startPrank(USER2);
        tokenA.approve(address(router), AMOUNT_DESIRED);

        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountA.selector);
        router.addLiquidityETH{value: SMALL_AMOUNT_DESIRED}(
            address(tokenA), AMOUNT_DESIRED, IMPOSSIBLE_AMOUNT_MIN, STRICT_AMOUNT_MIN, USER2, block.timestamp
        );

        vm.stopPrank();
    }

    function testAddLiquidityETHRevertsIfInsufficientETHAmount() public {
        _addLiquidityETH(USER1, tokenA);

        vm.deal(USER2, AMOUNT_DESIRED);

        vm.startPrank(USER2);
        tokenA.approve(address(router), SMALL_AMOUNT_DESIRED);

        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountB.selector);
        router.addLiquidityETH{value: AMOUNT_DESIRED}(
            address(tokenA), SMALL_AMOUNT_DESIRED, STRICT_AMOUNT_MIN, IMPOSSIBLE_AMOUNT_MIN, USER2, block.timestamp
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/
    function testRemoveLiquidityWorks() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountA, uint256 amountB) = _removeLiquidity(USER1, tokenA, tokenB, liquidity);

        // Assert returned amounts
        assertEq(amountA, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountB, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // User received tokens back
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);

        // LP tokens burned
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);

        // Only permanently locked liquidity remains
        assertEq(UniswapV2Pair(pair).totalSupply(), LOCKED_LIQUIDITY);

        // Reserves equal locked liquidity
        _assertReserves(pair, LOCKED_LIQUIDITY, LOCKED_LIQUIDITY);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(UniswapV2Pair(pair).balanceOf(address(router)), 0);
    }

    function testRemoveLiquidityWorksWithUnsortedTokens() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountB, uint256 amountA) = _removeLiquidity(USER1, tokenB, tokenA, liquidity);

        // Assert
        assertEq(amountA, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountB, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);

        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);
    }

    function testRemoveLiquidityRemovesPartialLiquidity() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1) / 2;

        // Act
        (uint256 amountA, uint256 amountB) = _removeLiquidity(USER1, tokenA, tokenB, liquidity);

        // Assert returned amounts
        assertEq(amountA, liquidity);
        assertEq(amountB, liquidity);

        // Half of the LP should remain
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), AMOUNT_DESIRED - LOCKED_LIQUIDITY - liquidity);

        // Total supply decreases by the burned liquidity
        assertEq(UniswapV2Pair(pair).totalSupply(), AMOUNT_DESIRED - liquidity);

        // User received the redeemed tokens
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - AMOUNT_DESIRED + amountA);

        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - AMOUNT_DESIRED + amountB);

        // Reserves decrease proportionally
        _assertReserves(pair, AMOUNT_DESIRED - amountA, AMOUNT_DESIRED - amountB);
    }

    function testRemoveLiquidityRevertsIfDeadlineExpired() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        vm.startPrank(USER1);
        UniswapV2Pair(pair).approve(address(router), liquidity);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.removeLiquidity(address(tokenA), address(tokenB), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline);

        vm.stopPrank();
    }

    function testRemoveLiquidityRevertsIfInsufficientAmountA() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        vm.startPrank(USER1);
        UniswapV2Pair(pair).approve(address(router), liquidity);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountA.selector);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            AMOUNT_DESIRED, // greater than actual amount returned
            AMOUNT_MIN,
            USER1,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testRemoveLiquidityRevertsIfInsufficientAmountB() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        vm.startPrank(USER1);
        UniswapV2Pair(pair).approve(address(router), liquidity);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountB.selector);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            AMOUNT_MIN,
            AMOUNT_DESIRED, // greater than actual amount returned
            USER1,
            block.timestamp
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          REMOVE LIQUIDITY ETH
    //////////////////////////////////////////////////////////////*/
    function testRemoveLiquidityETHWorks() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountToken, uint256 amountETH) = _removeLiquidityETH(USER1, tokenA, liquidity);

        // Assert returned amounts
        assertEq(amountToken, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountETH, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // User received token and ETH
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(USER1.balance, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // User should not receive WETH
        assertEq(weth.balanceOf(USER1), 0);

        // LP tokens burned
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);

        // Only permanently locked liquidity remains
        assertEq(UniswapV2Pair(pair).totalSupply(), LOCKED_LIQUIDITY);

        // Reserves equal locked liquidity
        _assertReserves(pair, LOCKED_LIQUIDITY, LOCKED_LIQUIDITY);

        // Router should never retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function testRemoveLiquidityETHRevertsIfDeadlineExpired() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        vm.startPrank(USER1);
        UniswapV2Pair(pair).approve(address(router), liquidity);

        uint256 deadline = block.timestamp;
        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.removeLiquidityETH(address(tokenA), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline);

        vm.stopPrank();
    }

    function testRemoveLiquidityETHRevertsIfInsufficientTokenAmount() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        vm.startPrank(USER1);
        UniswapV2Pair(pair).approve(address(router), liquidity);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountA.selector);
        router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            AMOUNT_DESIRED, // greater than actual amount returned
            AMOUNT_MIN,
            USER1,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testRemoveLiquidityETHRevertsIfInsufficientETHAmount() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        vm.startPrank(USER1);
        UniswapV2Pair(pair).approve(address(router), liquidity);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__InsufficientAmountB.selector);
        router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            AMOUNT_MIN,
            AMOUNT_DESIRED, // greater than actual ETH amount returned
            USER1,
            block.timestamp
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                      REMOVE LIQUIDITY WITH PERMIT
    //////////////////////////////////////////////////////////////*/
    function testRemoveLiquidityWithPermitWorks() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountA, uint256 amountB) = _removeLiquidityWithPermit(liquidity, false);

        // Assert returned amounts
        assertEq(amountA, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountB, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // LP burned
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);

        // User received underlying assets
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);

        // Only permanently locked liquidity remains
        assertEq(UniswapV2Pair(pair).totalSupply(), LOCKED_LIQUIDITY);

        // Reserves updated
        _assertReserves(pair, LOCKED_LIQUIDITY, LOCKED_LIQUIDITY);

        // Router should not retain any assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(UniswapV2Pair(pair).balanceOf(address(router)), 0);
    }

    function testRemoveLiquidityWithPermitApprovesMaxLiquidity() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountA, uint256 amountB) = _removeLiquidityWithPermit(liquidity, true);

        // Assert returned amounts
        assertEq(amountA, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountB, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // LP burned
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);

        // Max allowance should not be decremented by transferFrom
        assertEq(UniswapV2Pair(pair).allowance(USER1, address(router)), type(uint256).max);

        // Only permanently locked liquidity remains
        assertEq(UniswapV2Pair(pair).totalSupply(), LOCKED_LIQUIDITY);
    }

    function testRemoveLiquidityWithPermitRevertsIfDeadlineExpired() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);
        uint256 deadline = block.timestamp;

        bytes32 digest = _getPermitDigest(liquidity, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER1_PRIVATE_KEY, digest);

        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline, false, v, r, s
        );
    }

    function testRemoveLiquidityWithPermitRevertsIfPermitInvalid() public {
        // Arrange
        (address pair,,,) = _addLiquidity(USER1, tokenA, tokenB);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);
        uint256 deadline = block.timestamp;

        bytes32 digest = _getPermitDigest(liquidity, deadline);

        // Sign with the WRONG private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER2_PRIVATE_KEY, digest);

        // Act
        vm.expectRevert();
        router.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline, false, v, r, s
        );
    }

    function testRemoveLiquidityETHWithPermitWorks() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountToken, uint256 amountETH) = _removeLiquidityETHWithPermit(liquidity, false);

        // Assert returned amounts
        assertEq(amountToken, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountETH, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // User received underlying assets
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(USER1.balance, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // User should not receive WETH
        assertEq(weth.balanceOf(USER1), 0);

        // LP burned
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);

        // Only permanently locked liquidity remains
        assertEq(UniswapV2Pair(pair).totalSupply(), LOCKED_LIQUIDITY);

        // Reserves updated
        _assertReserves(pair, LOCKED_LIQUIDITY, LOCKED_LIQUIDITY);

        // Router should not retain any assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function testRemoveLiquidityETHWithPermitApprovesMaxLiquidity() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);

        // Act
        (uint256 amountToken, uint256 amountETH) = _removeLiquidityETHWithPermit(liquidity, true);

        // Assert returned amounts
        assertEq(amountToken, AMOUNT_DESIRED - LOCKED_LIQUIDITY);
        assertEq(amountETH, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // LP burned
        assertEq(UniswapV2Pair(pair).balanceOf(USER1), 0);

        // Max allowance should not be decremented
        assertEq(UniswapV2Pair(pair).allowance(USER1, address(router)), type(uint256).max);

        // User received underlying assets
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(USER1.balance, AMOUNT_DESIRED - LOCKED_LIQUIDITY);

        // Router should not retain assets
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function testRemoveLiquidityETHWithPermitRevertsIfDeadlineExpired() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);
        uint256 deadline = block.timestamp;

        bytes32 digest = _getETHPermitDigest(liquidity, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER1_PRIVATE_KEY, digest);

        vm.warp(deadline + 1);

        // Act
        vm.expectRevert(IUniswapV2Router.UniswapV2Router__Expired.selector);
        router.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline, false, v, r, s
        );
    }

    function testRemoveLiquidityETHWithPermitRevertsIfPermitInvalid() public {
        // Arrange
        (address pair,,,) = _addLiquidityETH(USER1, tokenA);

        uint256 liquidity = UniswapV2Pair(pair).balanceOf(USER1);
        uint256 deadline = block.timestamp;

        bytes32 digest = _getETHPermitDigest(liquidity, deadline);

        // Sign with the WRONG private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER2_PRIVATE_KEY, digest);

        // Act
        vm.expectRevert();
        router.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline, false, v, r, s
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function _addLiquidity(address user, ERC20Mock token0, ERC20Mock token1)
        internal
        returns (address pair, uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        vm.startPrank(user);
        token0.approve(address(router), AMOUNT_DESIRED);
        token1.approve(address(router), AMOUNT_DESIRED);

        // Act
        (amount0, amount1, liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            AMOUNT_DESIRED,
            AMOUNT_DESIRED,
            STRICT_AMOUNT_MIN,
            STRICT_AMOUNT_MIN,
            user,
            block.timestamp
        );
        vm.stopPrank();

        pair = factory.getPair(address(token0), address(token1));
    }

    function _getPair(ERC20Mock token0, ERC20Mock token1) internal view returns (UniswapV2Pair) {
        return UniswapV2Pair(factory.getPair(address(token0), address(token1)));
    }

    function _addLiquidityETH(address user, ERC20Mock token)
        internal
        returns (address pair, uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        vm.deal(user, AMOUNT_DESIRED);

        vm.startPrank(user);

        token.approve(address(router), AMOUNT_DESIRED);

        (amountToken, amountETH, liquidity) = router.addLiquidityETH{value: AMOUNT_DESIRED}(
            address(token), AMOUNT_DESIRED, STRICT_AMOUNT_MIN, STRICT_AMOUNT_MIN, user, block.timestamp
        );

        vm.stopPrank();

        pair = factory.getPair(address(token), address(weth));
    }

    function _assertReserves(address pair, uint256 expectedReserve0, uint256 expectedReserve1) internal view {
        (uint112 reserve0, uint112 reserve1,) = UniswapV2Pair(pair).getReserves();

        assertEq(reserve0, uint112(expectedReserve0));
        assertEq(reserve1, uint112(expectedReserve1));
    }

    function _removeLiquidity(address user, ERC20Mock token0, ERC20Mock token1, uint256 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        UniswapV2Pair pair = _getPair(token0, token1);

        vm.startPrank(user);

        pair.approve(address(router), liquidity);

        (amount0, amount1) = router.removeLiquidity(
            address(token0), address(token1), liquidity, AMOUNT_MIN, AMOUNT_MIN, user, block.timestamp
        );

        vm.stopPrank();
    }

    function _removeLiquidityETH(address user, ERC20Mock token, uint256 liquidity)
        internal
        returns (uint256 amountToken, uint256 amountETH)
    {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(token), address(weth)));

        vm.startPrank(user);

        pair.approve(address(router), liquidity);

        (amountToken, amountETH) =
            router.removeLiquidityETH(address(token), liquidity, AMOUNT_MIN, AMOUNT_MIN, user, block.timestamp);

        vm.stopPrank();
    }

    // so the user in this helper is harcoded to USER1, to avoid stack too deep errors
    // and its tokenA and tokenB are also hardcoded to the test's tokenA and tokenB, to avoid stack too deep errors
    function _removeLiquidityWithPermit(uint256 liquidity, bool approveMax)
        internal
        returns (uint256 amountA, uint256 amountB)
    {
        uint256 value = approveMax ? type(uint256).max : liquidity;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(value);

        vm.prank(USER1);

        (amountA, amountB) = router.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidity,
            AMOUNT_MIN,
            AMOUNT_MIN,
            USER1,
            block.timestamp,
            approveMax,
            v,
            r,
            s
        );
    }

    function _signPermit(uint256 value) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = _getPermitDigest(value, block.timestamp);

        (v, r, s) = vm.sign(USER1_PRIVATE_KEY, digest);
    }

    function _getPermitDigest(uint256 value, uint256 deadline) internal view returns (bytes32 digest) {
        bytes32 structHash;
        UniswapV2Pair pair;
        {
            pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
            uint256 nonce = pair.nonces(USER1);

            structHash = keccak256(abi.encode(PERMIT_TYPEHASH, USER1, address(router), value, nonce, deadline));
        }

        digest = keccak256(abi.encodePacked("\x19\x01", pair.DOMAIN_SEPARATOR(), structHash));
    }

    function _removeLiquidityETHWithPermit(uint256 liquidity, bool approveMax)
        internal
        returns (uint256 amountToken, uint256 amountETH)
    {
        uint256 value = approveMax ? type(uint256).max : liquidity;
        uint256 deadline = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = _signETHPermit(value, deadline);

        vm.prank(USER1);

        (amountToken, amountETH) = router.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, AMOUNT_MIN, AMOUNT_MIN, USER1, deadline, approveMax, v, r, s
        );
    }

    function _signETHPermit(uint256 value, uint256 deadline) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = _getETHPermitDigest(value, deadline);

        (v, r, s) = vm.sign(USER1_PRIVATE_KEY, digest);
    }

    function _getETHPermitDigest(uint256 value, uint256 deadline) internal view returns (bytes32 digest) {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(weth)));

        bytes32 structHash;

        {
            uint256 nonce = pair.nonces(USER1);

            structHash = keccak256(abi.encode(PERMIT_TYPEHASH, USER1, address(router), value, nonce, deadline));
        }

        digest = keccak256(abi.encodePacked("\x19\x01", pair.DOMAIN_SEPARATOR(), structHash));
    }
}
