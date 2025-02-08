// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// @notice HelperConfig is a script that provides configuration for the network
// @dev This specific script only works for Testnets with deployed Uniswap V4 Contracts
// @dev Also needs an installation of SwapRouter and ModifyLiquidityRouter
contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    error HelperConfig__UnsupportedNetwork();

    struct NetworkConfig {
        address poolManagerAddress;
        address hookAddress;
        address hookOwnerAndDeployerAddress;
        uint256 hookOwnerAndDeployerPrivateKey;
        address poolSwapTestAddress;
        address poolModifyLiquidityTestAddress;
        address create2DeployerAddress;
        address agentAdress;
        uint256 agentPrivateKey;
        address swapperAddress;
        uint256 swapperPrivateKey;
        address liquidityProviderAddress;
        uint256 liquidityProviderPrivateKey;
        address USDCAddress;
        address LINKAddress;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            revert HelperConfig__UnsupportedNetwork();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            poolManagerAddress: vm.envAddress("SEPOLIA_MAINNET_DEPLOYED_POOL_MANAGER_ADDRESS"),
            hookAddress: vm.envAddress("SEPOLIA_MAINNET_DEPLOYED_HOOK_ADDRESS"),
            hookOwnerAndDeployerAddress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"), 
            hookOwnerAndDeployerPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            poolSwapTestAddress: vm.envAddress("SEPOLIA_MAINNET_DEPLOYED_POOL_SWAP_TEST_ADDRESS"),
            poolModifyLiquidityTestAddress: vm.envAddress("SEPOLIA_MAINNET_DEPLOYED_POOL_MODIFY_LIQUIDITY_TEST_ADDRESS"),
            create2DeployerAddress: vm.envAddress("CREATE2_DEPLOYER_ADDRESS"),
            agentAdress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"),
            agentPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            swapperAddress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"),
            swapperPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            liquidityProviderAddress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"),
            liquidityProviderPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            USDCAddress: vm.envAddress("SEPOLIA_MAINNET_DEPLOYED_USDC_ADDRESS"),
            LINKAddress: vm.envAddress("SEPOLIA_MAINNET_DEPLOYED_LINK_ADDRESS") // Note: LINK CANNOT be minted on Sepolia Mainnet
        });
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory config = getSepoliaEthConfig();
        config.poolManagerAddress = vm.envAddress("BASE_SEPOLIA_DEPLOYED_POOL_MANAGER_ADDRESS");
        config.hookAddress = vm.envAddress("BASE_SEPOLIA_DEPLOYED_HOOK_ADDRESS");
        config.poolSwapTestAddress = vm.envAddress("BASE_SEPOLIA_DEPLOYED_POOL_SWAP_TEST_ADDRESS");
        config.poolModifyLiquidityTestAddress = vm.envAddress("BASE_SEPOLIA_DEPLOYED_POOL_MODIFY_LIQUIDITY_TEST_ADDRESS");
        config.USDCAddress = vm.envAddress("BASE_SEPOLIA_DEPLOYED_USDC_ADDRESS");
        config.LINKAddress = vm.envAddress("BASE_SEPOLIA_DEPLOYED_LINK_ADDRESS"); // Note: LINK CAN be minted on Base Sepolia
        return config;
    }
}
