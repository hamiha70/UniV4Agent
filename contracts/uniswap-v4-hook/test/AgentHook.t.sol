// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AgentHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

contract AgentHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    AgentHook public hook;
    // Test Addresses
    address public HOOK_OWNER = makeAddr("HOOK_OWNER");
    address public AGENT = makeAddr("AGENT");
    
    // Events from AgentHook contract
    event AgentAuthorized(address indexed agent);
    event AgentUnauthorized(address indexed agent);
    event PoolRegistered(bytes32 indexed poolId);
    event PoolUnregistered(bytes32 indexed poolId);
    event PoolDamped(bytes32 indexed poolId, uint160 dampedSqrtPriceX96);
    event PoolUndamped(bytes32 indexed poolId);
    
    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployAndMint2Currencies();
        address hookAddress = address(uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        // Deploy the hook to an address with the correct flags
        deployCodeTo("AgentHook", abi.encode(manager, HOOK_OWNER), hookAddress);
        hook = AgentHook(hookAddress);
    }

    function test_InitialState() public view{
        assertEq(hook.s_hookOwner(), HOOK_OWNER);
        assertFalse(hook.isAuthorizedAgent(AGENT));
    }
}