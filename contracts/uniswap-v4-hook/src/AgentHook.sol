// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/base/hooks/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";


contract AgentHook is BaseHook {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

/*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
//////////////////////////////////////////////////////////////*/

    address public s_hookOwner;
    mapping(address => bool) public s_isAuthorizedAgent;
    mapping(PoolId => bool) public s_isRegisteredPool;
    mapping(PoolId => bool) public s_isDampedPool;
    mapping(PoolId => uint160) public s_dampedSqrtPriceX96;

/*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
//////////////////////////////////////////////////////////////*/

    constructor(IPoolManager _poolManager, address _hookOwner) BaseHook(_poolManager) {
        s_hookOwner = _hookOwner;
    }

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
        return (this.afterInitialize.selector);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // Extract the delta from the swap that we need to gi
        int128 hookDeltaUnspecified = params.zeroForOne ? delta.amount1() : delta.amount0();
        Currency currency = params.zeroForOne ? key.currency1 : key.currency0;
        // If the pool is not in damped state, we can give the delta to the swapper
        if (!s_isDampedPool[key.toId()]) {
            // Emit event that swap is happening at the pool's current price
            emit SwapAtPoolPrice(key.toId(), hookDeltaUnspecified, params.zeroForOne);
            poolManager.take(
                currency,
                msg.sender,    // The swapper
                uint256(int256(hookDeltaUnspecified))
            );
            return (this.afterSwap.selector, hookDeltaUnspecified);
        }
        // If the pool is in damped state, we need to calculate the delta that the hook and the swapper will share
        // determine the delta that the hook and the swapper will share
        int128 hookTokenOut;
        int128 swapperTokenOut;
        uint160 dampedSqrtPriceX96 = getDampedSqrtPriceX96(key.toId());
        uint160 poolSqrtPriceX96 = calculatePoolSqrtPriceX96FromBalanceDeltaAndSwapParams(params, delta);

        // Need to distinguish between zeroForOne and oneForZero
        if (params.zeroForOne) {
            if (poolSqrtPriceX96 < dampedSqrtPriceX96) {
                // token0 -> token1: price = dampedSqrtPriceX96 / poolSqrtPriceX96
                revert AgentHook_DampedPoolPriceTooHigh(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96);
            }
            swapperTokenOut = int128(int256(
                (uint256(uint128(hookDeltaUnspecified >= 0 ? hookDeltaUnspecified : -hookDeltaUnspecified)) * 
                uint256(dampedSqrtPriceX96) / uint256(poolSqrtPriceX96) * 
                uint256(dampedSqrtPriceX96) / uint256(poolSqrtPriceX96))
            ));
            hookTokenOut = hookDeltaUnspecified - swapperTokenOut;
            if (hookTokenOut < 0) {
                revert AgentHook_SwapAmountTooLarge(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96, hookTokenOut, swapperTokenOut);
            }
        }

        if (!params.zeroForOne) {
            if (poolSqrtPriceX96 > dampedSqrtPriceX96) {
                revert AgentHook_DampedPoolPriceTooLow(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96);
            }
            swapperTokenOut = int128(int256(
                (uint256(uint128(hookDeltaUnspecified >= 0 ? hookDeltaUnspecified : -hookDeltaUnspecified)) * 
                uint256(poolSqrtPriceX96) / uint256(dampedSqrtPriceX96) * 
                uint256(poolSqrtPriceX96) / uint256(dampedSqrtPriceX96))
            ));
            hookTokenOut = hookDeltaUnspecified - swapperTokenOut;
            if (hookTokenOut < 0) {
                revert AgentHook_SwapAmountTooLarge(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96, hookTokenOut, swapperTokenOut);
            }
        }

        // Distribute to the swapper and the hook
        // Emit event that swap is happening at the damped price
        emit SwapAtDampedPrice(key.toId(), swapperTokenOut, hookTokenOut, dampedSqrtPriceX96, poolSqrtPriceX96);
        poolManager.take(
            currency,
            msg.sender, // The swapper
            uint256(int256(swapperTokenOut))
        );
        poolManager.take(
            currency,
            address(this), // The hook
            uint256(int256(hookTokenOut))
        );

        return (this.afterSwap.selector, hookDeltaUnspecified);
    }

/*//////////////////////////////////////////////////////////////
                           PUBLIC & EXTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/

    function calculateSwapReturnSimplified(
        int128 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceX96
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
    }

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
/*//////////////////////////////////////////////////////////////
                           SETTERS
//////////////////////////////////////////////////////////////*/

    function setAuthorizedAgent(address agent, bool authorized) public {
        s_isAuthorizedAgent[agent] = authorized;
    }

    function setDampedPool(PoolId id, bool damped) public onlyAuthorizedAgent {
        s_isDampedPool[id] = damped;
    }

    function setDampedSqrtPriceX96(PoolId id, uint160 sqrtPriceX96) public onlyAuthorizedAgent {
        s_dampedSqrtPriceX96[id] = sqrtPriceX96;
    }
    function setHookOwner(address hookOwner) public onlyHookOwner {
        s_hookOwner = hookOwner;
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

    event HookOwnerSet(address hookOwner);      
    event AuthorizedAgentSet(address agent, bool authorized);
    event DampedPoolSet(PoolId id, bool damped);
    event DampedSqrtPriceX96Set(PoolId id, uint160 sqrtPriceX96);
    event PoolRegistered(PoolKey key);
    event SwapAtPoolPrice(PoolId indexed id, int128 indexed swapperTokenOut, bool indexed zeroForOne);
    event SwapAtDampedPrice(PoolId indexed id, int128 indexed swapperTokenOut, int128 indexed hookTokenOut, uint160 dampedSqrtPriceX96, uint160 poolSqrtPriceX96);
}
