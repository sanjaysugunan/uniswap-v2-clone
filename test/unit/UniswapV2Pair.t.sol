// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract UniswapV2PairTest is Test {
    UniswapV2Factory public factory;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    UniswapV2Pair public pair;

    address USER1 = makeAddr("user1");
    address USER2 = makeAddr("user2");

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD; // to lock token since address(0) throws error in oz's ERC20

    uint256 constant STARTING_USER_BALANCE = 10 ether;
    uint256 constant EXTRA_TOKEN_AMOUNT = 5 ether;
    uint256 constant INITIAL_LIQUIDITY = 1 ether;
    uint256 constant SWAP_INPUT = 0.01 ether;
    uint256 constant INVALID_SWAP_OUTPUT = 0.5 ether;
    uint256 LOCKED_LIQUIDITY;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function setUp() public {
        factory = new UniswapV2Factory();
        tokenA = new ERC20Mock(); // tokenA < tokenB
        tokenB = new ERC20Mock();
        pair = UniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));
        tokenA.mint(USER1, STARTING_USER_BALANCE);
        tokenB.mint(USER1, STARTING_USER_BALANCE);
        tokenA.mint(USER2, STARTING_USER_BALANCE);
        tokenB.mint(USER2, STARTING_USER_BALANCE);
        LOCKED_LIQUIDITY = pair.MINIMUM_LIQUIDITY();
    }

    function testFactoryAddressFromPair() public view {
        assertEq(address(factory), UniswapV2Pair(pair).factory());
    }

    function testInitializeReverts() public {
        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__NotFactory.selector);
        pair.initialize(address(tokenA), address(tokenB));
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/
    function testMintRevertsWithoutTokenTransfer() public {
        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientLiquidityMinted.selector);
        pair.mint(USER1);
    }

    function testFirstMint() public {
        _firstMint();

        // MINIMUM_LIQUIDITY is permanently locked in the first mint
        assertEq(pair.balanceOf(USER1) + LOCKED_LIQUIDITY, INITIAL_LIQUIDITY);
        assertEq(pair.totalSupply(), INITIAL_LIQUIDITY);
        assertEq(pair.balanceOf(BURN_ADDRESS), LOCKED_LIQUIDITY);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        _assertPairBalances(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
    }

    function testSecondMint() public {
        _firstMint();

        _mintLiquidity(USER2, USER2, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        assertEq(pair.balanceOf(USER2), INITIAL_LIQUIDITY);
    }

    function testSecondMintRevertsWithoutTokenTransfer() public {
        _firstMint();
        vm.startPrank(USER2);
        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientLiquidityMinted.selector);
        pair.mint(USER2);
        vm.stopPrank();
    }

    function testSecondMintRevertsIfOneTokenInsufficientLiquidity() public {
        _firstMint();
        vm.startPrank(USER2);
        // should be revert even if one token is insufficient
        tokenA.transfer(address(pair), INITIAL_LIQUIDITY);
        tokenB.transfer(address(pair), 0);
        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientLiquidityMinted.selector);
        pair.mint(USER2);
        vm.stopPrank();
    }

    function testSecondMintUsesMinimumLiquidityFormula() public {
        _firstMint();

        _mintLiquidity(USER2, USER2, EXTRA_TOKEN_AMOUNT, INITIAL_LIQUIDITY);
        // should only mint min liquidity of both tokens
        assertEq(pair.balanceOf(USER2), INITIAL_LIQUIDITY);
    }

    function testSecondMintUpdatesReserves() public {
        _firstMint();
        _mintLiquidity(USER2, USER2, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        _assertReserves(INITIAL_LIQUIDITY * 2, INITIAL_LIQUIDITY * 2);
    }

    function testMintEmits() public {
        vm.startPrank(USER1);
        tokenA.transfer(address(pair), INITIAL_LIQUIDITY);
        tokenB.transfer(address(pair), INITIAL_LIQUIDITY);

        vm.expectEmit(true, false, false, true, address(pair));
        emit Mint(USER1, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        pair.mint(USER1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                  BURN
    //////////////////////////////////////////////////////////////*/
    function testBurnRevertsIfNotMinted() public {
        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientLiquidityBurned.selector);
        pair.burn(USER1);
    }

    function testBurnRevertsIfZeroLPTokensTransferred() public {
        _firstMint();
        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientLiquidityBurned.selector);
        pair.burn(USER1);
    }

    function testBurnWorks() public {
        _firstMint();

        _burnAll(USER1);

        assertEq(pair.balanceOf(USER1), 0);
        assertEq(pair.totalSupply(), LOCKED_LIQUIDITY);
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - LOCKED_LIQUIDITY);
        _assertReserves(LOCKED_LIQUIDITY, LOCKED_LIQUIDITY);
    }

    function testBurnHalfLiquidityWorks() public {
        _firstMint();

        uint256 halfBalance = pair.balanceOf(USER1) / 2;

        vm.startPrank(USER1);
        pair.transfer(address(pair), halfBalance);
        pair.burn(USER1);
        vm.stopPrank();

        assertEq(pair.balanceOf(USER1), halfBalance);
        assertEq(pair.totalSupply(), halfBalance + LOCKED_LIQUIDITY);
        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - INITIAL_LIQUIDITY + halfBalance);
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - INITIAL_LIQUIDITY + halfBalance);
        _assertReserves(halfBalance + LOCKED_LIQUIDITY, halfBalance + LOCKED_LIQUIDITY);
    }

    function testBurnEmits() public {
        _firstMint();

        uint256 balanceBefore = pair.balanceOf(USER1);
        vm.startPrank(USER1);

        pair.transfer(address(pair), balanceBefore);
        vm.expectEmit(true, true, false, true, address(pair));
        emit Burn(USER1, INITIAL_LIQUIDITY - LOCKED_LIQUIDITY, INITIAL_LIQUIDITY - LOCKED_LIQUIDITY, USER1);
        pair.burn(USER1);
        vm.stopPrank();
    }

    function testBurnReturnsOnlyProportionalShareAfterUnbalancedMint() public {
        // USER1 creates the initial pool.
        _firstMint();

        // USER2 provides liquidity in an incorrect ratio.
        // The excess tokenB is donated to the pool.
        _mintLiquidity(USER2, USER2, INITIAL_LIQUIDITY, EXTRA_TOKEN_AMOUNT);

        // Burn all LP tokens owned by USER2.
        _burnAll(USER2);

        // USER2 burned all of their LP tokens.
        assertEq(pair.balanceOf(USER2), 0);
        assertEq(pair.totalSupply(), INITIAL_LIQUIDITY);

        // USER2 receives back only their proportional share of the pool.
        // The excess tokenB deposited during mint is not refunded.
        assertEq(tokenA.balanceOf(USER2), STARTING_USER_BALANCE);
        assertEq(tokenB.balanceOf(USER2), STARTING_USER_BALANCE - 2 ether);

        // The donated tokenB remains in the pool, benefiting the remaining LP.
        _assertReserves(INITIAL_LIQUIDITY, 3 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                  SWAP
    //////////////////////////////////////////////////////////////*/
    function testSwapRevertsIfAmountsOutIsZero() public {
        _firstMint();

        _transferToPair(USER2, tokenA, SWAP_INPUT);

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientOutputAmount.selector);
        pair.swap(0, 0, USER1, new bytes(0));
    }

    function testSwapRevertsIfAmountsOutIsGreaterThanReserve() public {
        _firstMint();

        _transferToPair(USER2, tokenA, SWAP_INPUT);

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientLiquidity.selector);
        pair.swap(0, EXTRA_TOKEN_AMOUNT, USER1, new bytes(0));
    }

    function testSwapRevertsIfInvalidToAddress() public {
        _firstMint();

        _transferToPair(USER2, tokenA, SWAP_INPUT);

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair_InvalidTo.selector);
        pair.swap(SWAP_INPUT, 0, address(tokenA), new bytes(0));
    }

    function testSwapRevertsIfInsufficientInputAmount() public {
        _firstMint();

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__InsufficientInputAmount.selector);
        pair.swap(0, SWAP_INPUT, USER1, new bytes(0));
    }

    function testSwapRevertsIfKDecrease() public {
        _firstMint();

        _transferToPair(USER2, tokenA, SWAP_INPUT);

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__K.selector);
        pair.swap(0, INVALID_SWAP_OUTPUT, USER2, new bytes(0));
    }

    function testSwapWorks() public {
        _firstMint();

        (uint256 reserveIn, uint256 reserveOut,) = pair.getReserves();
        uint256 maxAmount1Out = _getMaxOutput(reserveIn, reserveOut, SWAP_INPUT);

        _transferToPair(USER2, tokenA, SWAP_INPUT);

        pair.swap(0, maxAmount1Out, USER2, new bytes(0));

        assertEq(tokenA.balanceOf(USER2), STARTING_USER_BALANCE - SWAP_INPUT);
        assertEq(tokenB.balanceOf(USER2), STARTING_USER_BALANCE + maxAmount1Out);
        _assertReserves(INITIAL_LIQUIDITY + SWAP_INPUT, INITIAL_LIQUIDITY - maxAmount1Out);
        assertEq(tokenA.balanceOf(address(pair)), INITIAL_LIQUIDITY + SWAP_INPUT);
        assertEq(tokenB.balanceOf(address(pair)), INITIAL_LIQUIDITY - maxAmount1Out);
        assertEq(pair.totalSupply(), INITIAL_LIQUIDITY);
    }

    function testSwapEmits() public {
        _firstMint();

        (uint256 reserveIn, uint256 reserveOut,) = pair.getReserves();
        uint256 maxAmount1Out = _getMaxOutput(reserveIn, reserveOut, SWAP_INPUT);

        _transferToPair(USER2, tokenA, SWAP_INPUT);

        vm.prank(USER2);

        vm.expectEmit(true, true, false, true, address(pair));
        emit Swap(USER2, SWAP_INPUT, 0, 0, maxAmount1Out, USER2);
        pair.swap(0, maxAmount1Out, USER2, new bytes(0));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                  SKIM
    //////////////////////////////////////////////////////////////*/
    function testSkimWorks() public {
        _firstMint();

        _donate(USER1, SWAP_INPUT, SWAP_INPUT);

        _assertPairBalances(INITIAL_LIQUIDITY + SWAP_INPUT, INITIAL_LIQUIDITY + SWAP_INPUT);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        pair.skim(USER2);

        _assertPairBalances(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        assertEq(tokenA.balanceOf(USER2), STARTING_USER_BALANCE + SWAP_INPUT);
        assertEq(tokenB.balanceOf(USER2), STARTING_USER_BALANCE + SWAP_INPUT);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        // LP balances doesnt affect
        assertEq(pair.balanceOf(USER1), INITIAL_LIQUIDITY - pair.MINIMUM_LIQUIDITY());
        assertEq(pair.balanceOf(USER2), 0);
    }

    function testSkimHasNoEffectsWithoutExtraTokens() public {
        _firstMint();

        _assertPairBalances(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        pair.skim(USER2);

        _assertPairBalances(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
    }

    /*//////////////////////////////////////////////////////////////
                                  SYNC
    //////////////////////////////////////////////////////////////*/
    function testSyncWorks() public {
        _firstMint();

        _donate(USER1, SWAP_INPUT, SWAP_INPUT);

        _assertPairBalances(INITIAL_LIQUIDITY + SWAP_INPUT, INITIAL_LIQUIDITY + SWAP_INPUT);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        pair.sync();

        _assertPairBalances(INITIAL_LIQUIDITY + SWAP_INPUT, INITIAL_LIQUIDITY + SWAP_INPUT);
        _assertReserves(INITIAL_LIQUIDITY + SWAP_INPUT, INITIAL_LIQUIDITY + SWAP_INPUT);

        assertEq(pair.totalSupply(), INITIAL_LIQUIDITY); // sync should never mint or burn LP Tokens
        assertEq(pair.balanceOf(USER1), INITIAL_LIQUIDITY - pair.MINIMUM_LIQUIDITY()); // shouldn't affect LP Balances
        assertEq(pair.balanceOf(USER2), 0);

        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - INITIAL_LIQUIDITY - SWAP_INPUT); // sync shouldn't transfer anything
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - INITIAL_LIQUIDITY - SWAP_INPUT);
    }

    function testSyncHasNoEffectsWithoutExtraTokens() public {
        _firstMint();

        _assertPairBalances(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        pair.sync();

        _assertPairBalances(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        _assertReserves(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        assertEq(pair.totalSupply(), INITIAL_LIQUIDITY); // sync should never mint or burn LP Tokens
        assertEq(pair.balanceOf(USER1), INITIAL_LIQUIDITY - pair.MINIMUM_LIQUIDITY()); // shouldn't affect LP Balances
        assertEq(pair.balanceOf(USER2), 0);

        assertEq(tokenA.balanceOf(USER1), STARTING_USER_BALANCE - INITIAL_LIQUIDITY); // sync shouldn't transfer anything
        assertEq(tokenB.balanceOf(USER1), STARTING_USER_BALANCE - INITIAL_LIQUIDITY);
    }

    function testSyncEmits() public {
        _firstMint();

        _donate(USER1, SWAP_INPUT, SWAP_INPUT);

        vm.expectEmit(false, false, false, true, address(pair));
        emit Sync(uint112(INITIAL_LIQUIDITY + SWAP_INPUT), uint112(INITIAL_LIQUIDITY + SWAP_INPUT));
        pair.sync();
    }

    function testSyncUpdatesPriceAccumulatorsAfterTimeElapsed() public {
        vm.warp(100);

        pair.sync();

        (,, uint32 blockTimestampLast) = pair.getReserves();
        assertEq(blockTimestampLast, 100);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL FUNCTIONS IN UNISWAPV2PAIR
    //////////////////////////////////////////////////////////////*/
    function testSafeTransferRevertsIfTransferFailed() public {
        MockFailedTransfer badToken = new MockFailedTransfer();

        ERC20Mock goodToken = new ERC20Mock();
        address badPair = factory.createPair(address(badToken), address(goodToken));

        badToken.mint(USER1, STARTING_USER_BALANCE);
        goodToken.mint(USER1, STARTING_USER_BALANCE);

        vm.startPrank(USER1);
        badToken.transfer(badPair, SWAP_INPUT);
        goodToken.transfer(badPair, SWAP_INPUT);
        vm.stopPrank();

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__TransferFailed.selector);
        UniswapV2Pair(badPair).skim(USER1);
    }

    function testUpdateReservesRevertsIfBalanceExceedsUint112Max() public {
        uint256 moreThanUint112Max = uint256(type(uint112).max) + 1;
        tokenA.mint(USER1, moreThanUint112Max);

        _donate(USER1, moreThanUint112Max, SWAP_INPUT);

        vm.expectRevert(IUniswapV2Pair.UniswapV2Pair__Overflow.selector);
        pair.sync();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _firstMint() internal {
        _mintLiquidity(USER1, USER1, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
    }

    function _mintLiquidity(address from, address to, uint256 amountA, uint256 amountB) internal {
        vm.startPrank(from);
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        pair.mint(to);
        vm.stopPrank();
    }

    function _assertReserves(uint256 expected0, uint256 expected1) internal view {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        assertEq(reserve0, uint112(expected0));
        assertEq(reserve1, uint112(expected1));
    }

    function _burnAll(address user) internal {
        uint256 balanceBefore = pair.balanceOf(user);
        vm.startPrank(user);

        pair.transfer(address(pair), balanceBefore);
        pair.burn(user);
        vm.stopPrank();
    }

    function _transferToPair(address user, ERC20Mock token, uint256 amount) internal {
        vm.prank(user);
        token.transfer(address(pair), amount);
    }

    function _getMaxOutput(uint256 reserveIn, uint256 reserveOut, uint256 amountIn) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (reserveOut * amountInWithFee) / (reserveIn * 1000 + amountInWithFee);
    }

    function _donate(address user, uint256 amount0, uint256 amount1) public {
        vm.startPrank(user);
        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);
        vm.stopPrank();
    }

    function _assertPairBalances(uint256 amount0, uint256 amount1) internal view {
        assertEq(tokenA.balanceOf(address(pair)), amount0);
        assertEq(tokenB.balanceOf(address(pair)), amount1);
    }
}
