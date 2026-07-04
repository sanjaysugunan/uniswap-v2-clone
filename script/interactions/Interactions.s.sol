// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";
import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";

contract Interactions is Script {
    function getRouter() public view returns (UniswapV2Router) {
        return UniswapV2Router(payable(DevOpsTools.get_most_recent_deployment("UniswapV2Router", block.chainid)));
    }

    function getFactory() public view returns (UniswapV2Factory) {
        return UniswapV2Factory(DevOpsTools.get_most_recent_deployment("UniswapV2Factory", block.chainid));
    }
}

