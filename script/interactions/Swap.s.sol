// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Interactions} from "./Interactions.s.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";

contract Swap is Interactions {
    function run() external {
        UniswapV2Router router = getRouter();

        // Replace with your deployed token addresses
        address tokenIn = address(0);
        address tokenOut = address(0);

        swapExactTokensForTokens(router, tokenIn, tokenOut, 1 ether);
    }

    function swapExactTokensForTokens(UniswapV2Router router, address tokenIn, address tokenOut, uint256 amountIn)
        public
    {
        vm.startBroadcast();

        IERC20(tokenIn).approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        router.swapExactTokensForTokens(amountIn, 0, path, msg.sender, block.timestamp);

        vm.stopBroadcast();
    }
}
