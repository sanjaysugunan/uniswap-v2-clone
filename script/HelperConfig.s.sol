// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "test/mocks/WETH9.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 internal constant ANVIL_CHAIN_ID = 31337;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 internal constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = _getAnvilConfig();
        } else if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = _getSepoliaConfig();
        } else {
            revert("Unsupported chain");
        }
    }

    function _getSepoliaConfig() internal view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c, // Sepolia WETH used by UniswapV2
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        WETH9 weth = new WETH9();
        vm.stopBroadcast();

        return NetworkConfig({weth: address(weth), deployerKey: DEFAULT_ANVIL_PRIVATE_KEY});
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
