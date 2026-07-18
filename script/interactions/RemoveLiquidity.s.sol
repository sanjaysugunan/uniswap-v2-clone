// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Interactions} from "./Interactions.s.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";

contract RemoveLiquidity is Interactions {
    function run() external {
        UniswapV2Router router = getRouter();

        // Replace with your deployed token addresses
        address tokenA = address(0);
        address tokenB = address(0);

        uint256 liquidity = 1 ether;

        removeLiquidity(router, tokenA, tokenB, liquidity);
    }

    function removeLiquidity(UniswapV2Router router, address tokenA, address tokenB, uint256 liquidity) public {
        address pair = getFactory().getPair(tokenA, tokenB);

        vm.startBroadcast();

        IERC20(pair).approve(address(router), liquidity);

        router.removeLiquidity(tokenA, tokenB, liquidity, 0, 0, msg.sender, block.timestamp);

        vm.stopBroadcast();
    }
}
