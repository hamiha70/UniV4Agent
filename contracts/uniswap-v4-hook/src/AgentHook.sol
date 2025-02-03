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
                revert DampedPoolPriceTooHigh(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96);
            }
            swapperTokenOut = int128(int256(
                (uint256(uint128(abs(hookDeltaUnspecified))) * uint256(dampedSqrtPriceX96) / uint256(poolSqrtPriceX96) * uint256(dampedSqrtPriceX96) / uint256(poolSqrtPriceX96))
            ));
            hookTokenOut = hookDeltaUnspecified - swapperTokenOut;
            if (hookTokenOut < 0) {
                revert SwapAmountTooLarge(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96, hookTokenOut, swapperTokenOut);
            }
        }

        if (!params.zeroForOne) {
            if (poolSqrtPriceX96 > dampedSqrtPriceX96) {
                revert DampedPoolPriceTooLow(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96);
            }
            swapperTokenOut = int128(int256(
                (uint256(uint128(abs(hookDeltaUnspecified))) * uint256(poolSqrtPriceX96) / uint256(dampedSqrtPriceX96) * uint256(poolSqrtPriceX96) / uint256(dampedSqrtPriceX96))
            ));
            hookTokenOut = hookDeltaUnspecified - swapperTokenOut;
            if (hookTokenOut < 0) {
                revert SwapAmountTooLarge(key.toId(), poolSqrtPriceX96, dampedSqrtPriceX96, hookTokenOut, swapperTokenOut);
            }
        }

        // Distribute to the swapper and the hook
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

    function calculatePoolSqrtPriceX96FromBalanceDeltaAndSwapParams(IPoolManager.SwapParams calldata params, BalanceDelta delta) public pure returns (uint160) {
        // Calculate the poolSqrtPriceX96 from the balance delta and the swap params
        // poolSqrtPriceX96 = sqrt(balanceDelta / amountIn)
        uint160 poolSqrtPriceX96 = uint160(uint256(uint128(abs(delta.amount1()))) / uint256(params.amountSpecified));
        return poolSqrtPriceX96;
    }


/*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/

    function abs(int128 x) internal pure returns (int128) {
        return x >= 0 ? x : -x;
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
        if (!s_isAuthorizedAgent[msg.sender]) revert NotAuthorizedAgent();
        _;
    }   

    modifier onlyHookOwner() {
        if (msg.sender != s_hookOwner) revert NotHookOwner();
        _;
    }
/*//////////////////////////////////////////////////////////////        
                           ERRORS
//////////////////////////////////////////////////////////////*/

    error NotAuthorizedAgent();
    error NotHookOwner();
    error DampedPoolPriceTooHigh(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96);
    error DampedPoolPriceTooLow(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96);
    error SwapAmountTooLarge(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96, int128 hookTokenOut, int128 swapperTokenOut);
/*//////////////////////////////////////////////////////////////
                           EVENTS
//////////////////////////////////////////////////////////////*/

    event HookOwnerSet(address hookOwner);      
    event AuthorizedAgentSet(address agent, bool authorized);
    event DampedPoolSet(PoolId id, bool damped);
    event DampedSqrtPriceX96Set(PoolId id, uint160 sqrtPriceX96);
    event SwapAtDampedPrice(PoolId indexed id, int128 indexed swapperTokenOut, int128 indexed hookTokenOut, uint160 dampedSqrtPriceX96, uint160 poolSqrtPriceX96, PoolKey key);
}