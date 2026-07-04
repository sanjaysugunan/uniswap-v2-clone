// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "test/mocks/WETH9.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 internal constant ANVIL_CHAIN_ID = 31337;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    constructor() {
        if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = _getAnvilConfig();
        } else if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = _getSepoliaConfig();
        } else {
            revert("Unsupported chain");
        }
    }

    function _getSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c // Sepolia WETH used by UniswapV2
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        WETH9 weth = new WETH9();
        vm.stopBroadcast();

        return NetworkConfig({weth: address(weth)});
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
