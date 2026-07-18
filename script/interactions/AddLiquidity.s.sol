// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Interactions} from "./Interactions.s.sol";

import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AddLiquidity is Interactions {
    function run() external {
        UniswapV2Router router = getRouter();

        // Replace these with your deployed token addresses
        address tokenA = address(0);
        address tokenB = address(0);

        addLiquidity(router, tokenA, tokenB, 10 ether, 10 ether);
    }

    function addLiquidity(UniswapV2Router router, address tokenA, address tokenB, uint256 amountA, uint256 amountB)
        public
    {
        vm.startBroadcast();

        IERC20(tokenA).approve(address(router), amountA);
        IERC20(tokenB).approve(address(router), amountB);

        router.addLiquidity(tokenA, tokenB, amountA, amountB, 0, 0, msg.sender, block.timestamp);

        vm.stopBroadcast();
    }
}
