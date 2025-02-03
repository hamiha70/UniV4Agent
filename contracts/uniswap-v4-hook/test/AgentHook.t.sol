// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AgentHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

contract AgentHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    AgentHook public hook;

    // Constants
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;  // 1:1 price
    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    
    // Test Addresses
    address public HOOK_OWNER = makeAddr("HOOK_OWNER");
    address public AGENT = makeAddr("AGENT");
    address public NON_HOOK_OWNER = makeAddr("NON_HOOK_OWNER");
    address public NON_AGENT = makeAddr("NON_AGENT");
    
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

    modifier withAgent() {
        vm.startPrank(HOOK_OWNER);
        hook.setAuthorizedAgent(AGENT, true);
        vm.stopPrank();
        _;
    }

    modifier withPool() {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        // Initialize pool
        manager.initialize(poolKey, SQRT_RATIO_1_1);
        _;
    }

    function test_InitialState() public view {
        assertEq(hook.s_hookOwner(), HOOK_OWNER);
        assertFalse(hook.isAuthorizedAgent(AGENT));
    }

    function test_SetAgent_AsOwner() public {
        vm.startPrank(HOOK_OWNER);
        
        // Test authorizing an agent
        vm.expectEmit(true, false, false, true);
        emit AuthorizedAgentSet(AGENT, true);
        hook.setAuthorizedAgent(AGENT, true);
        assertTrue(hook.isAuthorizedAgent(AGENT));
        
        // Test unauthorizing the agent
        vm.expectEmit(true, false, false, true);
        emit AuthorizedAgentSet(AGENT, false);
        hook.setAuthorizedAgent(AGENT, false);
        assertFalse(hook.isAuthorizedAgent(AGENT));
        
        vm.stopPrank();
    }

    function test_SetAgent_AsNonOwner() public {
        vm.startPrank(NON_HOOK_OWNER);
        
        vm.expectRevert(AgentHook.AgentHook_NotHookOwner.selector);
        hook.setAuthorizedAgent(AGENT, true);
        
        assertFalse(hook.isAuthorizedAgent(AGENT));
        vm.stopPrank();
    }

        function test_SetHookOwner_AsOwner() public {
        address NEW_HOOK_OWNER = makeAddr("NEW_HOOK_OWNER");
        vm.startPrank(HOOK_OWNER);
        
        // Test changing hook owner
        vm.expectEmit(true, false, false, true);
        emit HookOwnerSet(NEW_HOOK_OWNER);
        hook.setHookOwner(NEW_HOOK_OWNER);
        assertEq(hook.s_hookOwner(), NEW_HOOK_OWNER);
        
        vm.stopPrank();
    }

    function test_SetHookOwner_AsNonOwner() public {
        address NEW_HOOK_OWNER = makeAddr("NEW_HOOK_OWNER");
        vm.startPrank(NON_HOOK_OWNER);
        
        vm.expectRevert(AgentHook.AgentHook_NotHookOwner.selector);
        hook.setHookOwner(NEW_HOOK_OWNER);
        
        assertEq(hook.s_hookOwner(), HOOK_OWNER);
        vm.stopPrank();
    }

    function test_PoolInitialization() public {
        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        // Initialize pool and expect event
        vm.expectEmit(false, false, false, true);
        emit PoolRegistered(poolKey);
        
        manager.initialize(poolKey, SQRT_RATIO_1_1);

        // Verify pool is registered in hook
        assertTrue(hook.isRegisteredPool(poolKey.toId()));
    }

    function test_GetCurrentPoolPrice() public withPool {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        uint160 currentPrice = hook.getCurrentSqrtPriceX96(poolKey.toId());
        assertEq(currentPrice, SQRT_RATIO_1_1);
    }

    function test_GetCurrentDampedPrice_Unset() public withPool {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        uint160 dampedPrice = hook.getDampedSqrtPriceX96(poolKey.toId());
        assertEq(dampedPrice, 0);
    }

    function test_GetCurrentPoolKey() public withPool {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        PoolKey memory storedKey = hook.getPoolKey(poolKey.toId());
        assertEq(Currency.unwrap(storedKey.currency0), Currency.unwrap(poolKey.currency0));
        assertEq(Currency.unwrap(storedKey.currency1), Currency.unwrap(poolKey.currency1));
        assertEq(storedKey.fee, poolKey.fee);
        assertEq(storedKey.tickSpacing, poolKey.tickSpacing);
        assertEq(address(storedKey.hooks), address(poolKey.hooks));
    }
}