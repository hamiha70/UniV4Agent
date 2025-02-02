// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AgentHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract AgentHookTest is Test {
    address public constant HOOK_OWNER = address(0x1);
    address public constant POOL_MANAGER = address(0x2);
    AgentHook public hook;
    
    function setUp() public {
        // Deploy a mock pool manager
        hook = new AgentHook(IPoolManager(POOL_MANAGER), HOOK_OWNER);
    }

}