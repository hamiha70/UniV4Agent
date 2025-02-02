// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {AgentHook} from "../src/AgentHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract DeployHook is Script {
    address public constant HOOK_OWNER = address(0x1);
    address public constant POOL_MANAGER = address(0x2);

    function run() public {
        vm.startBroadcast();
        // Deploy hook with a mock pool manager address for testing
        new AgentHook(IPoolManager(POOL_MANAGER), HOOK_OWNER);
        vm.stopBroadcast();
    }
}
