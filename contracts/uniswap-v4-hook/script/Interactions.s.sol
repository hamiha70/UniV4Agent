// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HelperConfig} from "./HelperConfig.s.sol";
import {AgentHook} from "../src/AgentHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract SetAuthorizedAgent is Script {
    address hookAddress;
    uint256 hookOwnerAndDeployerPrivateKey;
    address agentAddress;


    constructor() {
        HelperConfig helperConfig = new HelperConfig();
        (/*address _poolManagerAddress*/,
        address _hookAddress,
        /*address _hookOwnerAndDeployerAddress*/,
        uint256 _hookOwnerAndDeployerPrivateKey,
        /*address _poolSwapTestAddress*/, 
        /*address _poolModifyLiquidityTestAddress*/,
        /*address _create2DeployerAddress*/, 
        address _agentAddress, 
        /*uint256 _agentPrivateKey*/, 
        /*address _swapperAddress*/, 
        /*uint256 _swapperPrivateKey*/, 
        /*address _liquidityProviderAddress*/, 
        /*uint256 _liquidityProviderPrivateKey*/, 
        /*address _USDCAddress*/, 
        /*address _LINKAddress*/
        ) = helperConfig.activeNetworkConfig();

        hookAddress = _hookAddress;
        hookOwnerAndDeployerPrivateKey = _hookOwnerAndDeployerPrivateKey;
        agentAddress = _agentAddress;
    }

    function setAuthorizedAgent(bool isAuthorized) public {
        vm.startBroadcast(hookOwnerAndDeployerPrivateKey);
        AgentHook(hookAddress).setAuthorizedAgent(agentAddress, isAuthorized);
        vm.stopBroadcast();
    }
    
    function run() external {
        setAuthorizedAgent(true);
    }
}