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
        address hookOwnerAddress;
        uint256 hookOwnerPrivateKey;
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
            poolManagerAddress: 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543,
            hookOwnerAddress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"), 
            hookOwnerPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            poolSwapTestAddress: 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe,
            poolModifyLiquidityTestAddress: 0x0C478023803a644c94c4CE1C1e7b9A087e411B0A,
            create2DeployerAddress: vm.envAddress("CREATE2_DEPLOYER_ADDRESS"),
            agentAdress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"),
            agentPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            swapperAddress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"),
            swapperPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            liquidityProviderAddress: vm.envAddress("SEPOLIA_ACCOUNT_ADDRESS_1"),
            liquidityProviderPrivateKey: vm.envUint("SEPOLIA_ACCOUNT_PRIVATE_KEY_1"),
            USDCAddress: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
        });
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory config = getSepoliaEthConfig();
        config.poolManagerAddress = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
        config.poolSwapTestAddress = 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9;
        config.poolModifyLiquidityTestAddress = 0x37429cD17Cb1454C34E7F50b09725202Fd533039;
        config.USDCAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        return config;
    }
}
