// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {TokenA} from "../src/tokens/TokenA.sol";
import {TokenB} from "../src/tokens/TokenB.sol";
import {TokenC} from "../src/tokens/TokenC.sol";

contract DeployTokens is Script {
    function run() external returns (TokenA, TokenB, TokenC) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast(config.account);

        TokenA tokenA = new TokenA();
        TokenB tokenB = new TokenB();
        TokenC tokenC = new TokenC();

        vm.stopBroadcast();

        console2.log("========================");
        console2.log(" Faucet Tokens Deployed ");
        console2.log("========================");
        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        console2.log("TokenC:", address(tokenC));
        console2.log("========================");

        return (tokenA, tokenB, tokenC);
    }
}
