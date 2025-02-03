// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AgentHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

contract AgentHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    AgentHook public hook;
    
    // Test Addresses
    address public HOOK_OWNER = makeAddr("HOOK_OWNER");
    address public AGENT = makeAddr("AGENT");
    
    // Events from AgentHook contract
    event AuthorizedAgentSet(address indexed agent, bool authorized);
    event PoolRegistered(PoolKey key);
    event DampedPoolSet(PoolId indexed id, bool damped, uint160 dampedSqrtPriceX96, bool directionZeroForOne);
    event HookOwnerSet(address indexed hookOwner);
    event DampedPoolReset(PoolId indexed id);
    event SwapAtPoolPrice(PoolId indexed id, int128 hookDeltaUnspecified, bool zeroForOne);
    event SwapAtDampedPrice(PoolId indexed id, int128 swapperTokenOut, int128 hookTokenOut, uint160 dampedSqrtPriceX96, uint160 poolSqrtPriceX96);
    
    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployAndMint2Currencies();

        // Calculate hook address with all required flags
        address hookAddress = address(uint160(
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_INITIALIZE_FLAG
        ));
        
        // Deploy the hook to an address with the correct flags
        deployCodeTo("AgentHook", abi.encode(manager, HOOK_OWNER), hookAddress);
        hook = AgentHook(hookAddress);
    }

    function test_InitialState() public view{
        assertEq(hook.s_hookOwner(), HOOK_OWNER);
        assertFalse(hook.isAuthorizedAgent(AGENT));
    }
}