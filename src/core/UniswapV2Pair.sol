// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IUniswapV2Callee} from "../interfaces/IUniswapV2Callee.sol";
import {UQ112x112} from "../libraries/UQ112x112.sol"; // try to find a better way
// Oz library imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//so every UniswapV2Pair contract is also an UniswapV2ERC20 contract as well
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ112x112 for uint224;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public constant override MINIMUM_LIQUIDITY = 10 ** 3; // make sure this override works, not getter functions
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)"))); // for token transfers!!
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD; // to lock token since address(0) throws error in oz's ERC20

    address public override factory;
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
    modifier lock() {
        if (unlocked == 0) revert UniswapV2Pair__Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        factory = msg.sender;
    }

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

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external override {
        // check if theres a better way to do this
        if (msg.sender != factory) revert UniswapV2Pair__NotFactory();
        token0 = _token0;
        token1 = _token1;
    }

    // this low-level function should be called from a contract which performs important safety checks
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

    // this low-level function should be called from a contract which performs important safety checks
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

    // this low-level function should be called from a contract which performs important safety checks
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

    // force balances to match reserves
    function skim(address to) external override lock {
        address token0_ = token0; // gas savings
        address token1_ = token1; // gas savings
        _safeTransfer(token0_, to, IERC20(token0_).balanceOf(address(this)) - reserve0);
        _safeTransfer(token1_, to, IERC20(token1_).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external override lock {
        _updateReserves(
            IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1
        );
        emit Sync(reserve0, reserve1);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            // please look into the if conditon more
            revert UniswapV2Pair__TransferFailed();
        }
    }

    // update reserves and, on the first call per block, price accumulators
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
    // might not need these functions as they are in the interface
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
