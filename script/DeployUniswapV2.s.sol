// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {HelperConfig} from "./HelperConfig.s.sol";

import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {UniswapV2Router} from "src/periphery/UniswapV2Router.sol";

contract DeployUniswapV2 is Script {
    function run() external returns (UniswapV2Factory factory, UniswapV2Router router, address weth) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast(config.account);

        factory = new UniswapV2Factory();
        router = new UniswapV2Router(address(factory), config.weth);

        vm.stopBroadcast();

        weth = config.weth;

        console2.log("==================================");
        console2.log("Factory:", address(factory));
        console2.log("Router :", address(router));
        console2.log("WETH   :", weth);
        console2.log("==================================");
    }
}
