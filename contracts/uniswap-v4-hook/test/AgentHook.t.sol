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
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {MockERC20} from "@uniswap/v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract AgentHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

/*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
//////////////////////////////////////////////////////////////*/  
    AgentHook public hook;

/*//////////////////////////////////////////////////////////////
                            CONSTANTS
//////////////////////////////////////////////////////////////*/
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;  // 1:1 price
    uint160 constant SQRT_RATIO_2_1 = 112807967156250000000000000000; // 2:1 price
    uint160 constant SQRT_RATIO_1_2 = 56403983578125000000000000000; // 1:2 price
    uint160 constant MIN_SQRT_PRICE = TickMath.MIN_SQRT_PRICE + 1;
    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int128 constant LIQUIDITY_DELTA = 10 * 1e18;
    int128 constant AMOUNT_SPECIFIED = 1e16;
    
/*//////////////////////////////////////////////////////////////
                            ADDRESSES
//////////////////////////////////////////////////////////////*/
    address public HOOK_OWNER = makeAddr("HOOK_OWNER");
    address public AGENT = makeAddr("AGENT");
    address public NON_HOOK_OWNER = makeAddr("NON_HOOK_OWNER");
    address public NON_AGENT = makeAddr("NON_AGENT");
    
/*//////////////////////////////////////////////////////////////
                            EVENTS (from AgentHook)
//////////////////////////////////////////////////////////////*/
    event AuthorizedAgentSet(address indexed agent, bool authorized);
    event PoolRegistered(PoolKey key);
    event DampedPoolSet(PoolId indexed id, uint160 dampedSqrtPriceX96, bool directionZeroForOne);
    event HookOwnerSet(address indexed hookOwner);
    event DampedPoolReset(PoolId indexed id);
    event SwapAtPoolPrice(PoolId indexed id, int128 hookDeltaUnspecified, bool zeroForOne);
    event SwapAtDampedPrice(PoolId indexed id, int128 swapperTokenOut, int128 hookTokenOut, uint160 dampedSqrtPriceX96, uint160 poolSqrtPriceX96);
    
/*//////////////////////////////////////////////////////////////
                            SETUP
//////////////////////////////////////////////////////////////*/
    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployAndMint2Currencies();
        
        // Mint tokens to the test contract
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1000e18);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1000e18);
        
        // Approve the router to spend our tokens
        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);

        // Approve the router to spend our tokens
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);

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

/*//////////////////////////////////////////////////////////////
                           MODIFIERS
//////////////////////////////////////////////////////////////*/
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

    modifier withLiquidity() {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: LIQUIDITY_DELTA,
            salt: 0
        });

        modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);
        _;
    }

/*//////////////////////////////////////////////////////////////
                            BASIC TESTS
//////////////////////////////////////////////////////////////*/
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

    function test_SetDampedPool_AsAgent() public withAgent withPool {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        uint160 dampedPrice = SQRT_RATIO_2_1; // Double the current price
        bool directionZeroForOne = true;
        
        vm.startPrank(AGENT);
        vm.expectEmit(true, false, false, true);
        emit DampedPoolSet(poolKey.toId(), dampedPrice, directionZeroForOne);
        hook.setDampedPool(poolKey.toId(), dampedPrice, directionZeroForOne);
        
        assertTrue(hook.isDampedPool(poolKey.toId()));
        assertEq(hook.getDampedSqrtPriceX96(poolKey.toId()), dampedPrice);
        assertTrue(hook.getCurrentDirectionZeroForOne(poolKey.toId()));
        vm.stopPrank();
    }

    function test_SetDampedPool_AsNonAgent() public withPool {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        
        vm.startPrank(NON_AGENT);
        vm.expectRevert(AgentHook.AgentHook_NotAuthorizedAgent.selector);
        hook.setDampedPool(poolKey.toId(), SQRT_RATIO_1_1, true);
        vm.stopPrank();
    }

    function test_ResetDampedPool_AsOwner() public withAgent withPool {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        // First set the pool as damped
        vm.prank(AGENT);
        hook.setDampedPool(poolKey.toId(), SQRT_RATIO_1_1 * 2, true);
        
        // Then reset it as owner
        vm.startPrank(HOOK_OWNER);
        vm.expectEmit(true, false, false, true);
        emit DampedPoolReset(poolKey.toId());
        hook.resetDampedPool(poolKey.toId());
        
        assertFalse(hook.isDampedPool(poolKey.toId()));
        assertEq(hook.getDampedSqrtPriceX96(poolKey.toId()), 0);
        assertFalse(hook.getCurrentDirectionZeroForOne(poolKey.toId()));
        vm.stopPrank();
    }

    function test_ResetDampedPool_AsNonOwner() public withAgent withPool withLiquidity {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        // First set the pool as damped
        vm.prank(AGENT);
        hook.setDampedPool(poolKey.toId(), SQRT_RATIO_2_1, true);
        
        // Try to reset as non-owner
        vm.startPrank(NON_HOOK_OWNER);
        vm.expectRevert(AgentHook.AgentHook_NotHookOwner.selector);
        hook.resetDampedPool(poolKey.toId());
        vm.stopPrank();
        
        // Verify state hasn't changed
        assertTrue(hook.isDampedPool(poolKey.toId()));
        assertEq(hook.getDampedSqrtPriceX96(poolKey.toId()), SQRT_RATIO_2_1);
        assertTrue(hook.getCurrentDirectionZeroForOne(poolKey.toId()));
    }

/*//////////////////////////////////////////////////////////////
                            SWAP TESTS
//////////////////////////////////////////////////////////////*/
    function test_Swap_Undamped() public withPool withLiquidity {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        // Create swap params
        bool zeroForOne = true;
        uint160 sqrtPriceLimitX96 = MIN_SQRT_PRICE; // Minimum price limit

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: AMOUNT_SPECIFIED,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        uint256 token0balanceBefore = currency0.balanceOfSelf();
        uint256 token1balanceBefore = currency1.balanceOfSelf();

        // Prepare swap settings
        PoolSwapTest.TestSettings memory testSettings = 
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        // Calculate expected output using hook's calculation function
        int128 expectedOutput = hook.calculateSwapReturnSimplifiedAndUndamped(
            AMOUNT_SPECIFIED,
            zeroForOne,
            SQRT_RATIO_1_1,
            FEE
        );

        // Expect event emission
        vm.expectEmit(true, false, false, false);
        emit SwapAtPoolPrice(poolKey.toId(), expectedOutput, zeroForOne);
        // Perform swap
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 token0balanceAfter = currency0.balanceOfSelf();
        uint256 token1balanceAfter = currency1.balanceOfSelf();

        assertApproxEqRel(token0balanceAfter, token0balanceBefore - uint256(uint128(AMOUNT_SPECIFIED)), 1e12); // 0.0001
        assertApproxEqRel(token1balanceAfter, token1balanceBefore + uint256(uint128(expectedOutput)), 1e16); // 1% tolerance

        console.log("token0balanceDelta:", token0balanceBefore - token0balanceAfter);
        console.log("token1balanceDelta", token1balanceAfter - token1balanceBefore);

        // Verify final state
        assertFalse(hook.isDampedPool(poolKey.toId()));
    }

    function test_Swap_Damped() public withAgent withPool withLiquidity {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        // Set up damped pool with price LOWER than current price for zeroForOne swap
        // Current price is SQRT_RATIO_1_1, so we'll use SQRT_RATIO_1_2 (half the price)
        vm.prank(AGENT);
        hook.setDampedPool(poolKey.toId(), SQRT_RATIO_1_2, true);

        // Create swap params (same as undamped case)
        bool zeroForOne = true;
        uint160 sqrtPriceLimitX96 = MIN_SQRT_PRICE;

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: AMOUNT_SPECIFIED,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        uint256 token0balanceBefore = currency0.balanceOfSelf();
        uint256 token1balanceBefore = currency1.balanceOfSelf();
        uint256 hookToken0balanceBefore = currency0.balanceOf(address(hook));
        uint256 hookToken1balanceBefore = currency1.balanceOf(address(hook));

        // console.log("Test contract - Before swap - token0 balance:", token0balanceBefore);
        // console.log("Test contract - Before swap - token1 balance:", token1balanceBefore);
        // console.log("Test contract - Before swap - hook token0 balance:", hookToken0balanceBefore);
        // console.log("Test contract - Before swap - hook token1 balance:", hookToken1balanceBefore);

        // Prepare swap settings
        PoolSwapTest.TestSettings memory testSettings = 
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        // Calculate total output using hook's calculation function
        int128 totalOutput = hook.calculateSwapReturnSimplifiedAndUndamped(
            AMOUNT_SPECIFIED,
            zeroForOne,
            SQRT_RATIO_1_1,
            FEE
        );

        // Calculate expected output using hook's calculation function
        int128 expectedOutputSwappper = hook.calculateSwapReturnSimplified(
            poolKey.toId(),
            zeroForOne,
            AMOUNT_SPECIFIED
        );

        // Calculate expected output using hook's calculation function
        int128 expectedOutputHook = totalOutput - expectedOutputSwappper;

        // Expect event emission
        vm.expectEmit(true, false, false, false);
        emit SwapAtDampedPrice(poolKey.toId(), expectedOutputSwappper, expectedOutputHook, SQRT_RATIO_1_2, SQRT_RATIO_1_1);
        
        // Perform swap
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 token0balanceAfter = currency0.balanceOfSelf();
        uint256 token1balanceAfter = currency1.balanceOfSelf();
        uint256 hookToken0balanceAfter = currency0.balanceOf(address(hook));
        uint256 hookToken1balanceAfter = currency1.balanceOf(address(hook));

        // console.log("After swap - token0 balance:", token0balanceAfter);
        // console.log("After swap - token1 balance:", token1balanceAfter);
        // console.log("After swap - hook token0 balance:", hookToken0balanceAfter);
        // console.log("After swap - hook token1 balance:", hookToken1balanceAfter);

        logBalanceAfterMinusBalanceBefore("Test contract - After swap - token0 balance delta:", token0balanceAfter, token0balanceBefore);
        logBalanceAfterMinusBalanceBefore("Test contract - After swap - token1 balance delta:", token1balanceAfter, token1balanceBefore);
        logBalanceAfterMinusBalanceBefore("Test contract - After swap - hook token0 balance delta:", hookToken0balanceAfter, hookToken0balanceBefore);
        logBalanceAfterMinusBalanceBefore("Test contract - After swap - hook token1 balance delta:", hookToken1balanceAfter, hookToken1balanceBefore);

        // Verify token0 (input) was taken correctly
        assertApproxEqRel(token0balanceAfter, token0balanceBefore - uint256(uint128(AMOUNT_SPECIFIED)), 1e12);
        console.log("Test contract - After swap - token0 balance delta:", token0balanceAfter - token0balanceBefore);

        // Verify hook received token1 (unspecified/output token)
        assertEq(hookToken0balanceAfter, hookToken0balanceBefore);
        console.log("Test contract - After swap - hook token0 balance delta:", hookToken0balanceAfter - hookToken0balanceBefore);
        assertTrue(hookToken1balanceAfter > hookToken1balanceBefore);
        console.log("Test contract - After swap - hook token1 balance delta:", hookToken1balanceAfter - hookToken1balanceBefore);
        assertApproxEqRel(hookToken1balanceAfter, hookToken1balanceBefore + uint256(uint128(expectedOutputHook)), 1e16);
        console.log("Test contract - After swap - hook token1 balance delta:", hookToken1balanceAfter - hookToken1balanceBefore);

        // Verify swapper received token1
        assertTrue(token1balanceAfter > token1balanceBefore);
        console.log("Test contract - After swap - token1 balance delta:", token1balanceAfter - token1balanceBefore);
        assertApproxEqRel(token1balanceAfter, token1balanceBefore + uint256(uint128(expectedOutputSwappper)), 1e16);
        console.log("Test contract - After swap - token1 balance delta:", token1balanceAfter - token1balanceBefore);

        // Verify final state
        assertTrue(hook.isDampedPool(poolKey.toId()));
        console.log("Test contract - After swap - damped pool:", hook.isDampedPool(poolKey.toId()));
        assertEq(hook.getDampedSqrtPriceX96(poolKey.toId()), SQRT_RATIO_1_2);
        console.log("Test contract - After swap - damped price:", hook.getDampedSqrtPriceX96(poolKey.toId()));
        assertTrue(hook.getCurrentDirectionZeroForOne(poolKey.toId()));
        console.log("Test contract - After swap - current direction zero for one:", hook.getCurrentDirectionZeroForOne(poolKey.toId()));
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER TESTS
    //////////////////////////////////////////////////////////////*/    
    
    function test_WithLiquidity_Modifier() public withPool withLiquidity {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        // Get position info using the correct method with proper destructuring
        (uint128 liquidity,,) = manager.getPositionInfo(
            poolKey.toId(),
            address(modifyLiquidityRouter),
            -120,
            120,
            0
        );
        
        // Cast to uint256 for assertEq
        assertEq(uint256(liquidity), uint256(uint128(LIQUIDITY_DELTA)));

        // Get pool slot0 data to verify price hasn't changed
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolKey.toId());
        assertEq(sqrtPriceX96, SQRT_RATIO_1_1);

        // Verify we can swap against this liquidity
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: AMOUNT_SPECIFIED,
            sqrtPriceLimitX96: MIN_SQRT_PRICE
        });

        // This should not revert due to having liquidity
        PoolSwapTest.TestSettings memory testSettings = 
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(poolKey, params, testSettings, "");
    }
    /*//////////////////////////////////////////////////////////////    
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/    

    function logBalanceAfterMinusBalanceBefore(string memory label, uint256 balanceAfter, uint256 balanceBefore) internal pure {
        string memory source = "Test contract - ";

        if (balanceAfter - balanceBefore > 0) {
            console.log(source, label, "(+)", balanceAfter - balanceBefore);
        } else {
            console.log(source, label, "(-)", balanceAfter - balanceBefore);
        }
    }
}
