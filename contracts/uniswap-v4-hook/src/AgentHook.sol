// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/base/hooks/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {console2} from "forge-std/console2.sol";

contract AgentHook is BaseHook {
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

/*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
//////////////////////////////////////////////////////////////*/

    address public s_hookOwner;
    mapping(address => bool) s_isAuthorizedAgent;
    mapping(PoolId => bool) s_isRegisteredPool;
    mapping(PoolId => bool) s_isDampedPool;
    mapping(PoolId => uint160) s_dampedSqrtPriceX96;
    mapping(PoolId => bool) s_directionZeroForOne;
    mapping(PoolId => PoolKey) s_poolKey;
    // IPoolManager public poolManager; -> Inherited from Basehook

/*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
//////////////////////////////////////////////////////////////*/

    constructor(IPoolManager _poolManager, address _hookOwner) BaseHook(_poolManager) {
        s_hookOwner = _hookOwner;
    }
    // Bashook exposes the poolManager to the hook as a state variable

/*//////////////////////////////////////////////////////////////
                           HOOK FUNCTIONS
//////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24
    ) external override returns (bytes4) {
        // Emit event that new pool is registered with the hook
        emit PoolRegistered(key);
        s_isRegisteredPool[key.toId()] = true;
        s_poolKey[key.toId()] = key;
        return (this.afterInitialize.selector);
    }

    // @notice This function is called after a swap has executed
    // @dev NOTE: This implementation only works for PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false})
    // @param sender The address of the sender of the swap
    // @param key The key of the pool that the swap was executed in
    // @param params The parameters for the swap
    // @param delta The balance delta of the swap
    // @param hookData The data to pass through to the swap hooks
    // @return selector The selector of the function to call next
    // @return hookDeltaUnspecified The balance delta of the hook
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // Extract the delta from the swap
        (, Currency unspecifiedCurrency) = _sortCurrencies(key, params);
        int128 hookDeltaUnspecified = params.zeroForOne ? delta.amount0() : delta.amount1();
        /*//////////////////////////////////////////////////////////////
                           LOGGING FOR TESTING
        //////////////////////////////////////////////////////////////*/
        logPoolKey(key);
        console2.log("=== SWAP REQUEST ===");
        console2.log("Swap direction (zeroForOne):", params.zeroForOne);
        logInt256("Amount specified", params.amountSpecified);
        logUint160("sqrtPriceLimitX96", params.sqrtPriceLimitX96);
        console2.log("=== SWAP START ===");
        logInt128("Delta amount0", delta.amount0());
        logInt128("Delta amount1", delta.amount1());
        logInt128("Hook delta unspecified", hookDeltaUnspecified);
        console2.log("Specified currency index:", _nameSpecifiedCurrency(params));
        /*//////////////////////////////////////////////////////////////
                           END LOGGING FOR TESTING
        //////////////////////////////////////////////////////////////*/

        // If pool is not damped or wrong direction, return 0 delta (no hook action)
        if (!s_isDampedPool[key.toId()] || !s_directionZeroForOne[key.toId()]) {
            console2.log("=== UNDAMPED SWAP ===");
            emit SwapAtPoolPrice(key.toId(), hookDeltaUnspecified, params.zeroForOne);
            return (this.afterSwap.selector, 0);
        }

        console2.log("=== DAMPED SWAP ===");
        // For damped pools, calculate the split between hook and swapper
        int128 hookTokenOut;
        int128 swapperTokenOut;
        uint160 dampedSqrtPriceX96 = getDampedSqrtPriceX96(key.toId());
        uint160 poolSqrtPriceX96 = calculatePoolSqrtPriceX96FromBalanceDeltaAndSwapParams(params, delta);

        console2.log("Damped sqrt price:", dampedSqrtPriceX96);
        console2.log("Pool sqrt price:", poolSqrtPriceX96);

        // Calculate splits based on direction
        if (params.zeroForOne) {
            if (poolSqrtPriceX96 <= dampedSqrtPriceX96) {
                console2.log("=== REVERTING: POOL PRICE TOO LOW === Damped price below pool price for zeroForOne swap ===");
                revert AgentHook_DampedPoolPriceTooHigh(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96);
            }
            swapperTokenOut = hookDeltaUnspecified * 
                int128(int256((uint256(poolSqrtPriceX96) * uint256(poolSqrtPriceX96)) / 
                             (uint256(dampedSqrtPriceX96) * uint256(dampedSqrtPriceX96))));
            hookTokenOut = hookDeltaUnspecified - swapperTokenOut;
            if (hookTokenOut > 0) {
                console2.log("=== REVERTING: HOOK TOKEN OUT POSITIVE ===");
                revert AgentHook_SwapAmountTooLarge(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96, hookTokenOut, swapperTokenOut);
            }
        }

        if (!params.zeroForOne) {
            if (poolSqrtPriceX96 > dampedSqrtPriceX96) {
                console2.log("=== REVERTING: POOL PRICE TOO HIGH === Damped price above pool price for oneForZero swap ===");
                revert AgentHook_DampedPoolPriceTooLow(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96);
            }
            swapperTokenOut = hookDeltaUnspecified * 
                int128(int256((uint256(dampedSqrtPriceX96) * uint256(dampedSqrtPriceX96)) / 
                             (uint256(poolSqrtPriceX96) * uint256(poolSqrtPriceX96))));
            hookTokenOut = hookDeltaUnspecified - swapperTokenOut;
            if (hookTokenOut > 0) {
                console2.log("=== REVERTING: HOOK TOKEN OUT POSITIVE ===");
                revert AgentHook_SwapAmountTooLarge(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96, hookTokenOut, swapperTokenOut);
            }
        }

        /*//////////////////////////////////////////////////////////////
                           LOGGING FOR TESTING
        //////////////////////////////////////////////////////////////*/
        console2.log("=== CALCULATED SPLITS ===");
        logInt128("Calculated swapper token out", swapperTokenOut);
        logInt128("Calculated hook token out", hookTokenOut);
        /*//////////////////////////////////////////////////////////////
                           END LOGGING FOR TESTING
        //////////////////////////////////////////////////////////////*/
        
        logBalances("Before taking tokens:", unspecifiedCurrency);

        // Take hook's portion using _settleOrTake
        _settleOrTake(unspecifiedCurrency, hookTokenOut);

        // After taking hook's portion
        console2.log("Pool balance after take:", unspecifiedCurrency.balanceOf(address(poolManager)));
        console2.log("=== SWAP END ===");
        
        emit SwapAtDampedPrice(key.toId(), swapperTokenOut, hookTokenOut, dampedSqrtPriceX96, poolSqrtPriceX96);

        // Return the hook's portion as delta (what we handled)
        return (this.afterSwap.selector, hookTokenOut);
    }

/*//////////////////////////////////////////////////////////////
                           PUBLIC & EXTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/

    function calculateSwapReturnSimplifiedAndUndamped(
        int128 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceX96,
        uint24 fee
    ) public pure returns (int128 amountOut) {
        require(sqrtPriceX96 > 0, "Invalid sqrt price");

        // Convert sqrtPriceX96 to price with full precision
        // price = (sqrtPriceX96/2^96)^2
        uint256 price;
        if (zeroForOne) {
            // token0 -> token1: price = token1/token0
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192; // divide by 2^192 (2^96 * 2^96)
            // amountOut = amountIn * price
            amountOut = -int128(int256((uint256(int256(amountIn)) * price) >> 96));
        } else {
            // token1 -> token0: price = token0/token1 = 1/(token1/token0)
            price = (uint256(2**192) / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96))); // invert the price
            // amountOut = amountIn / price
            amountOut = -int128(int256((uint256(int256(amountIn)) * price) >> 96));
        }
        // Apply the fee to the amountOut. Fee is in hundredths of a bip (10000)
        // Fee comes from sum of lpFee and protocolFee
        amountOut = amountOut * int128(uint128(1_000_000_000 - uint256(fee))) / 1_000_000_000;
        return amountOut;
    }

    // This function is used to calculate the swap return simplified based on the pool's current state BEFORE the swap has executed
    // It DOES NOT take into account the slippage
    // It DOES take into account the fee
    // It is NOT USED to calculate the swap return for the swapper and the hook in the damped state because it is an approximation
    function calculateSwapReturnSimplified(
        PoolId poolId,
        bool zeroForOne,
        int128 amountIn
    ) public view returns (int128 amountOut) {
        uint160 dampedSqrtPriceX96 = getDampedSqrtPriceX96(poolId);
        uint160 poolSqrtPriceX96 = getCurrentSqrtPriceX96(poolId);
        uint24 fee = getCurrentFee(poolId);
        if (s_isDampedPool[poolId] && s_directionZeroForOne[poolId]) {
            return calculateSwapReturnSimplifiedAndUndamped(amountIn, zeroForOne, poolSqrtPriceX96, fee);
        } else {
            return calculateSwapReturnSimplifiedAndUndamped(amountIn, zeroForOne, dampedSqrtPriceX96, fee);
        }
    }

    // This function is used to calculate the sqrtPriceX96 from the balance delta and the swap params
    // It deduces it after the swap has executed through the poolManager
    // It is used to calculate the swap return for the swapper and the hook in the damped state
    // It does not introduce an approximation
    function calculatePoolSqrtPriceX96FromBalanceDeltaAndSwapParams(
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta
    ) public pure returns (uint160) {
        uint256 numerator;
        uint256 denominator;

        if (params.zeroForOne) {
            // token0 -> token1: price = amount1/amount0
            numerator = uint256(uint128(delta.amount1() >= 0 ? uint128(delta.amount1()) : uint128(-delta.amount1())));
            denominator = uint256(uint128(uint256(params.amountSpecified >= 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified))));
        } else {
            // token1 -> token0: price = amount0/amount1
            numerator = uint256(uint128(delta.amount0() >= 0 ? uint128(delta.amount0()) : uint128(-delta.amount0())));
            denominator = uint256(uint128(uint256(params.amountSpecified >= 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified))));
        }

        require(denominator > 0, "Invalid amount specified");
        
        // Calculate sqrt(price) * 2^96
        uint160 sqrtPriceX96 = uint160(
            (uint256(numerator) << 96) / uint256(denominator)
        );

        return sqrtPriceX96;
    }

/*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/

    function _sortCurrencies(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency specified, Currency unspecified)
    {
        (specified, unspecified) = (params.zeroForOne == (params.amountSpecified < 0))
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);
    }


    function _settleOrTake(Currency currency, int128 delta) internal {
        // negative amount means hook should take tokens
        // positive means hook should settle tokens
        if (delta < 0) {
            currency.take(poolManager, address(this), uint128(-delta), false);
        } else {
            currency.settle(poolManager, address(this), uint128(delta), false);
        }
    }

/*//////////////////////////////////////////////////////////////
                           GETTERS
//////////////////////////////////////////////////////////////*/

    function getDampedSqrtPriceX96(PoolId id) public view returns (uint160) {
        return s_dampedSqrtPriceX96[id];
    }

    function isDampedPool(PoolId id) public view returns (bool) {
        return s_isDampedPool[id];
    }

    function isRegisteredPool(PoolId id) public view returns (bool) {
        return s_isRegisteredPool[id];
    }

    function isAuthorizedAgent(address agent) public view returns (bool) {
        return s_isAuthorizedAgent[agent];
    } 

    function getCurrentSqrtPriceX96TickAndFees(PoolId poolId) public view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(poolManager, poolId);
    }

    function getCurrentSqrtPriceX96(PoolId poolId) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
    }

    function getCurrentDirectionZeroForOne(PoolId poolId) public view returns (bool) {
        return s_directionZeroForOne[poolId];
    }

    function getCurrentFee(PoolId poolId) public view returns (uint24 fee) {
        (, ,uint24 protocolFee, uint24 lpFee) = StateLibrary.getSlot0(poolManager, poolId);
        fee = protocolFee + lpFee;
    }

    function getPoolKey(PoolId poolId) public view returns (PoolKey memory) {
        return s_poolKey[poolId];
    }

/*//////////////////////////////////////////////////////////////
                           SETTERS
//////////////////////////////////////////////////////////////*/

    function setAuthorizedAgent(address agent, bool authorized) public onlyHookOwner {
        emit AuthorizedAgentSet(agent, authorized);
        s_isAuthorizedAgent[agent] = authorized;
    }

    function setDampedPool(PoolId id, uint160 _dampedSqrtPriceX96, bool _directionZeroForOne) public onlyAuthorizedAgent {
        emit DampedPoolSet(id, _dampedSqrtPriceX96, _directionZeroForOne);
        s_isDampedPool[id] = true;
        s_dampedSqrtPriceX96[id] = _dampedSqrtPriceX96;
        s_directionZeroForOne[id] = _directionZeroForOne;
    }

    function setHookOwner(address newHookOwner) public onlyHookOwner {
        emit HookOwnerSet(newHookOwner);
        s_hookOwner = newHookOwner;
    }

    function resetDampedPool(PoolId id) public onlyHookOwner {
        emit DampedPoolReset(id);
        s_isDampedPool[id] = false;
        s_dampedSqrtPriceX96[id] = 0;
        s_directionZeroForOne[id] = false;
    }
/*//////////////////////////////////////////////////////////////
                           MODIFIERS
//////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedAgent() {
        if (!s_isAuthorizedAgent[msg.sender]) revert AgentHook_NotAuthorizedAgent();
        _;
    }   

    modifier onlyHookOwner() {
        if (msg.sender != s_hookOwner) revert AgentHook_NotHookOwner();
        _;
    }
/*//////////////////////////////////////////////////////////////        
                           ERRORS
//////////////////////////////////////////////////////////////*/

    error AgentHook_NotAuthorizedAgent();
    error AgentHook_NotHookOwner();
    error AgentHook_DampedPoolPriceTooHigh(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96);
    error AgentHook_DampedPoolPriceTooLow(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96);
    error AgentHook_SwapAmountTooLarge(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96, int128 hookTokenOut, int128 swapperTokenOut);
/*//////////////////////////////////////////////////////////////
                           EVENTS
//////////////////////////////////////////////////////////////*/

    event HookOwnerSet(address indexed hookOwner);      
    event AuthorizedAgentSet(address indexed agent, bool authorized);
    event DampedPoolSet(PoolId indexed id, uint160 dampedSqrtPriceX96, bool directionZeroForOne);
    event DampedPoolReset(PoolId indexed id);
    event DampedSqrtPriceX96Set(PoolId indexed id, uint160 sqrtPriceX96);
    event PoolRegistered(PoolKey key);
    event SwapAtPoolPrice(PoolId indexed id, int128 swapperTokenOut, bool zeroForOne);
    event SwapAtDampedPrice(PoolId indexed id, int128 swapperTokenOut, int128 hookTokenOut, uint160 dampedSqrtPriceX96, uint160 poolSqrtPriceX96);


/*//////////////////////////////////////////////////////////////
                           UTILITIES FOR TESTING - REMOVE FOR PRODUCTION
//////////////////////////////////////////////////////////////*/

    function logInt128(string memory label, int128 value) internal pure {
        string memory source = "Hook - ";
        if (value < 0) {
            console2.log(source, label, "(-)", uint256(uint128(-value)));
        } else {
            console2.log(source, label, "(+)", uint256(uint128(value)));
        }
    }

    function logInt256(string memory label, int256 value) internal pure {
        string memory source = "Hook - ";
        if (value < 0) {
            console2.log(source, label, "(-)", uint256(-value));
        } else {
            console2.log(source, label, "(+)", uint256(value));
        }
    }

    function logUint160(string memory label, uint160 value) internal pure {
        string memory source = "Hook - ";
        console2.log(source, label, value);
    }

    function logInt24(string memory label, int24 value) internal pure {
        string memory source = "Hook - ";
        if (value < 0) {
            console2.log(source, label, "(-)", uint256(uint24(-value)));
        } else {
            console2.log(source, label, "(+)", uint256(uint24(value)));
        }
    }

    function logBalances(string memory label, Currency currency) internal view {
        string memory source = "Hook - ";
        console2.log(source, label);
        console2.log(source, "  Pool balance:", currency.balanceOf(address(poolManager)));
        console2.log(source, "  Hook balance:", currency.balanceOf(address(this)));
        console2.log(source, "  Test contract balance:", currency.balanceOf(address(this)));
    }

    function logPoolKey(PoolKey memory key) internal pure {
        string memory source = "Hook - ";
        console2.log(source, "Pool key:");
        console2.log(source, "  currency0:", Currency.unwrap(key.currency0));
        console2.log(source, "  currency1:", Currency.unwrap(key.currency1));
        console2.log(source, "  fee:", key.fee);
    }

    function logSwapParams(IPoolManager.SwapParams memory params) internal pure {
        string memory source = "Hook - ";
        console2.log(source, "Swap params:");
        console2.log(source, "  zeroForOne:", params.zeroForOne);
        logInt256(string.concat(source, "  amountSpecified:"), params.amountSpecified);
        logUint160(string.concat(source, "  sqrtPriceLimitX96:"), params.sqrtPriceLimitX96);
    }

    function _nameSpecifiedCurrency(IPoolManager.SwapParams calldata params) internal pure returns (uint256 specifiedCurrencyIndex) {
        if (params.zeroForOne == (params.amountSpecified > 0)) {
            specifiedCurrencyIndex = 0;
        } else {
            specifiedCurrencyIndex = 1;
        }
    }
}
