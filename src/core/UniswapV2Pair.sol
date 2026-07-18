// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IUniswapV2Callee} from "../interfaces/IUniswapV2Callee.sol";
import {UQ112x112} from "../libraries/UQ112x112.sol";
// Oz library imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniswapV2Pair
 * @author Sanjay Sugunan
 * @notice Implements a Uniswap V2 liquidity pool for a pair of ERC20 tokens.
 * @dev Manages liquidity provision, token swaps, reserve updates, LP token
 *      minting/burning, and price accumulation for TWAP calculations. Inherits
 *      UniswapV2ERC20 to represent liquidity provider (LP) tokens.
 */
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ112x112 for uint224;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public constant override MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)"))); // for token transfers!!
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD; // to lock token since address(0) throws error in oz's ERC20

    address public override factory; // i think i can keep this immutable
    address public override token0;
    address public override token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;

    uint256 private unlocked = 1;
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Prevents reentrant calls to protected functions.
     * @dev Implements a simple mutex by locking execution before the function body
     *      and unlocking afterward. Reverts if a protected function is entered
     *      while another protected function is already executing.
     */
    modifier lock() {
        if (unlocked == 0) revert UniswapV2Pair__Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the pair contract.
     * @dev Sets the factory as the deploying address. The factory is the only
     *      contract authorized to initialize the pair with its token addresses.
     */
    constructor() {
        factory = msg.sender;
    }

    /**
     * @notice Returns the current reserves and the last block timestamp.
     * @dev Reserves are stored in a single storage slot and returned as uint112 values
     *      for gas efficiency. The timestamp is truncated to 32 bits.
     * @return _reserve0 The reserve of token0.
     * @return _reserve1 The reserve of token1.
     * @return _blockTimestampLast The timestamp of the last reserve update.
     */
    function getReserves()
        public
        view
        override
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the pair with its two underlying tokens.
     * @dev Can only be called once by the factory immediately after deployment.
     *      Sets the immutable token addresses for the pair.
     * @param _token0 The address of the first token.
     * @param _token1 The address of the second token.
     */
    function initialize(address _token0, address _token1) external override {
        // check if theres a better way to do this
        if (msg.sender != factory) revert UniswapV2Pair__NotFactory();
        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Mints LP tokens in exchange for deposited liquidity.
     * @dev Calculates the liquidity to mint based on the current reserves and
     *      deposited token amounts. Permanently locks the minimum liquidity on
     *      the first mint and updates the pair reserves. This low-level function
     *      should only be called through the router or another contract that
     *      performs the necessary safety checks.
     * @param to The address receiving the newly minted LP tokens.
     * @return liquidity The amount of LP tokens minted.
     */
    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        uint256 totalSupply_ = totalSupply(); // totalSupply() is in UniswapV2ERC20
        if (totalSupply_ == 0) {
            // this multiplication won't overflow because the reserves are 112 bits
            uint256 rootK = Math.sqrt(amount0 * amount1);
            if (rootK <= MINIMUM_LIQUIDITY) revert UniswapV2Pair__InsufficientLiquidityMinted();

            liquidity = rootK - MINIMUM_LIQUIDITY;
            _mint(BURN_ADDRESS, MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min((amount0 * totalSupply_) / reserve0_, (amount1 * totalSupply_) / reserve1_);
        }
        if (liquidity == 0) revert UniswapV2Pair__InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _updateReserves(balance0, balance1, reserve0_, reserve1_);
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice Burns LP tokens and returns the underlying assets to the recipient.
     * @dev Calculates the amounts of token0 and token1 owed based on the caller's
     *      LP token balance, burns the LP tokens, transfers the underlying assets,
     *      and updates the pair reserves. This low-level function should only be
     *      called through the router or another contract that performs the
     *      necessary safety checks.
     * @param to The address receiving the underlying tokens.
     * @return amount0 The amount of token0 returned.
     * @return amount1 The amount of token1 returned.
     */
    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves(); // gas savings
        address token0_ = token0; // gas savings
        address token1_ = token1; // gas savings
        uint256 balance0 = IERC20(token0_).balanceOf(address(this));
        uint256 balance1 = IERC20(token1_).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 totalSupply_ = totalSupply(); // gas savings

        if (liquidity == 0) revert UniswapV2Pair__InsufficientLiquidityBurned(); // revert before division-by-zero errors

        amount0 = (liquidity * balance0) / totalSupply_;
        amount1 = (liquidity * balance1) / totalSupply_;
        if (amount0 == 0 || amount1 == 0) revert UniswapV2Pair__InsufficientLiquidityBurned(); // reverts for any rounding errors // not checked in tests yet
        _burn(address(this), liquidity);
        _safeTransfer(token0_, to, amount0);
        _safeTransfer(token1_, to, amount1);
        balance0 = IERC20(token0_).balanceOf(address(this));
        balance1 = IERC20(token1_).balanceOf(address(this));

        _updateReserves(balance0, balance1, reserve0_, reserve1_);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @notice Swaps one token for the other while preserving the constant product invariant.
     * @dev Transfers the requested output tokens, optionally invokes a callback for flash swaps,
     *      validates the input amounts and invariant, updates the reserves, and emits a Swap event.
     *      This low-level function should only be called through the router or another contract
     *      that performs the necessary safety checks.
     * @param amount0Out The amount of token0 to send to the recipient.
     * @param amount1Out The amount of token1 to send to the recipient.
     * @param to The address receiving the output tokens.
     * @param data Arbitrary data passed to the recipient for flash swap callbacks. Empty if no callback is required.
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external override lock {
        if (amount0Out == 0 && amount1Out == 0) revert UniswapV2Pair__InsufficientOutputAmount();
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        if (amount0Out > reserve0_ || amount1Out > reserve1_) revert UniswapV2Pair__InsufficientLiquidity();

        uint256 balance0;
        uint256 balance1;
        { // scope for _token{0,1}, avoids stack too deep errors and gas optimization // for new solidity versions compiler handles this better
            address token0_ = token0;
            address token1_ = token1;
            if (to == token0_ || to == token1_) revert UniswapV2Pair_InvalidTo();
            if (amount0Out > 0) _safeTransfer(token0_, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(token1_, to, amount1Out);
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(token0_).balanceOf(address(this));
            balance1 = IERC20(token1_).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > reserve0_ - amount0Out ? balance0 - (reserve0_ - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1_ - amount1Out ? balance1 - (reserve1_ - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert UniswapV2Pair__InsufficientInputAmount();
        { // scope for _token{0,1}, avoids stack too deep errors and gas optimization // for new solidity versions compiler handles this better
            uint256 balance0Adjusted = (balance0 * (1000)) - (amount0In * (3));
            uint256 balance1Adjusted = (balance1 * (1000)) - (amount1In * (3));
            if ((balance0Adjusted * balance1Adjusted) < uint256(reserve0_) * uint256(reserve1_) * (1000 ** 2)) {
                revert UniswapV2Pair__K();
            }
        }

        _updateReserves(balance0, balance1, reserve0_, reserve1_);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @notice Transfers any excess tokens held by the pair to the specified recipient.
     * @dev Sends the difference between the contract's token balances and the stored
     *      reserves to `to` without modifying the reserves. Primarily used to recover
     *      tokens accidentally sent to the pair contract.
     * @param to The address receiving the excess tokens.
     */
    function skim(address to) external override lock {
        address token0_ = token0; // gas savings
        address token1_ = token1; // gas savings
        _safeTransfer(token0_, to, IERC20(token0_).balanceOf(address(this)) - reserve0);
        _safeTransfer(token1_, to, IERC20(token1_).balanceOf(address(this)) - reserve1);
    }

    /**
     * @notice Updates the stored reserves to match the pair's current token balances.
     * @dev Synchronizes the reserves with the actual ERC20 balances held by the pair.
     *      Useful when tokens are transferred directly to the pair contract without
     *      interacting through the router or pair functions.
     */
    function sync() external override lock {
        _updateReserves(
            IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1
        );
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Safely transfers ERC20 tokens to a recipient.
     * @dev Performs a low-level call to the token's `transfer` function and
     *      reverts if the transfer fails or returns false. Supports ERC20 tokens
     *      that either return no value or a boolean success value.
     * @param token The address of the ERC20 token.
     * @param to The recipient of the tokens.
     * @param value The amount of tokens to transfer.
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            // please look into the if conditon more
            revert UniswapV2Pair__TransferFailed();
        }
    }

    /**
     * @notice Updates the pair reserves and cumulative price data.
     * @dev Synchronizes the stored reserves with the current token balances and,
     *      on the first update of each block, updates the cumulative price
     *      accumulators used for TWAP calculations. Reverts if either balance
     *      exceeds the maximum uint112 value.
     * @param balance0 The current balance of token0 held by the pair.
     * @param balance1 The current balance of token1 held by the pair.
     * @param _reserve0 The previous reserve of token0.
     * @param _reserve1 The previous reserve of token1.
     */
    function _updateReserves(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert UniswapV2Pair__Overflow();
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // function MINIMUM_LIQUIDITY() external pure returns (uint256) {
    //     return MINIMUM_LIQUIDITY;
    // }

    // function factory() external view returns (address) {
    //     return factory;
    // }

    // function token0() external view returns (address) {
    //     return token0;
    // }

    // function token1() external view returns (address) {
    //     return token1;
    // }

    // function price0CumulativeLast() external view returns (uint256) {
    //     return price0CumulativeLast;
    // }

    // function price1CumulativeLast() external view returns (uint256) {
    //     return price1CumulativeLast;
    // }
}
