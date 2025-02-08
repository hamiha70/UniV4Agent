// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HelperConfig} from "./HelperConfig.s.sol";
import {AgentHook} from "../src/AgentHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract ResetDampedPool is Script {

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
    }


    function resetDampedPool(address hookAddress) external {
        HelperConfig helperConfig = new HelperConfig();
        (address poolManagerAddress,
        address hookAddress,
        address hookOwnerAndDeployerAddress,
        uint256 hookOwnerAndDeployerPrivateKey,
        /*address poolSwapTestAddress*/, 
        /*address poolModifyLiquidityTestAddress*/,
        address create2DeployerAddress, 
        /*address agentAdress*/, 
        uint256 agentPrivateKey, 
        /*address swapperAddress*/, 
        /*uint256 swapperPrivateKey*/, 
        /*address liquidityProviderAddress*/, 
        /*uint256 liquidityProviderPrivateKey*/, 
        address USDCAddress, 
        address LINKAddress) = helperConfig.activeNetworkConfig();
        vm.startBroadcast(agentPrivateKey);
        vm.stopBroadcast();
    }
    
    
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        NetworkConfig memory networkConfig = helperConfig.activeNetworkConfig;
    }
}