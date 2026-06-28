// SPDX-License-Identifier: MIT

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
pragma solidity ^0.8.24;

import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
import {UniswapV2Pair} from "./UniswapV2Pair.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
// OZ imports
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract UniswapV2Factory is IUniswapV2Factory {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    // i think its not needed because its in interface
    // function getPair(address tokenA, address tokenB) external view returns (address pair) {
    //     return getPair[tokenA][tokenB];
    // }

    // function allPairs(uint256 index) external view returns (address pair) {
    //     return allPairs[index];
    // }
}
