// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {WETH9} from "../mocks/WETH9.sol";

contract UniswapV2RouterFuzzTest is Test {
    UniswapV2Factory internal factory;
    UniswapV2Router internal router;
    WETH9 internal weth;

    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;

    address internal USER = makeAddr("user");

    uint256 internal constant STARTING_BALANCE = 1_000_000 ether;

    function setUp() public {
        factory = new UniswapV2Factory();
        weth = new WETH9();
        router = new UniswapV2Router(address(factory), address(weth));

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        tokenA.mint(USER, STARTING_BALANCE);
        tokenB.mint(USER, STARTING_BALANCE);

        vm.startPrank(USER);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.stopPrank();
    }
}
