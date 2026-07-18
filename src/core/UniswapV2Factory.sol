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

import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
import {UniswapV2Pair} from "./UniswapV2Pair.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
// OZ imports
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title UniswapV2Factory
 * @author Sanjay Sugunan
 * @notice Deploys and manages Uniswap V2 trading pairs.
 * @dev Creates pair contracts using OpenZeppelin'sCREATE2 for deterministic addresses,
 *      maintains a registry of all deployed pairs, and prevents duplicate
 *      pair creation. Each unique token pair maps to a single UniswapV2Pair contract.
 */
contract UniswapV2Factory is IUniswapV2Factory {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Creates a new trading pair for two ERC20 tokens.
     * @dev Deploys the pair contract using OpenZeppelin'sCREATE2, initializes it, and stores
     *      the pair address in the factory's registry. Reverts if the tokens are
     *      identical, either token is the zero address, or the pair already exists.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pair The address of the newly created pair contract.
     */
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        if (tokenA == tokenB) revert UniswapV2Factory__IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert UniswapV2Factory__ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert UniswapV2Factory__PairExists();

        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = Create2.deploy(0, salt, bytecode);
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the total number of trading pairs created by the factory.
     * @return The total number of deployed pair contracts.
     */
    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    // function getPair(address tokenA, address tokenB) external view returns (address pair) {
    //     return getPair[tokenA][tokenB];
    // }

    // function allPairs(uint256 index) external view returns (address pair) {
    //     return allPairs[index];
    // }
}
