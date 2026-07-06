// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "test/mocks/WETH9.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        address account;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 internal constant ANVIL_CHAIN_ID = 31337;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    address internal BURNER_WALLET = 0xA3F294C501c1d5C1A83dc2238647704DB03827A5;
    address internal constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

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
            account: BURNER_WALLET
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        WETH9 weth = new WETH9();
        vm.stopBroadcast();

        return NetworkConfig({weth: address(weth), account: ANVIL_DEFAULT_ACCOUNT});
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
