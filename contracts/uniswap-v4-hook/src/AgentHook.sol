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

    mapping(address => bool) public s_isAuthorizedAgent;
    mapping(PoolId => bool) public s_isRegisteredPool;
    mapping(PoolId => bool) public s_isDampedPool;
    mapping(PoolId => uint160) public s_dampedSqrtPriceX96;

/*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
//////////////////////////////////////////////////////////////*/

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

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
        IPoolManager.InitializeParams calldata params,
        bytes calldata
    ) external override returns (bytes4, int128) {
        s_isRegisteredPool[key.toId()] = true;
        return (this.afterInitialize.selector, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        Currency currency = params.zeroForOne ? key.currency1 : key.currency0;
        // determine the delta that the hook and the swapper will share
        int128 hookDeltaUnspecified = params.zeroForOne ? delta.amount1() : delta.amount0();
        // Check if the pool is in damped state
        if (s_isDampedPool[key.toId()]) {
            // We need to share delta between the hook and the swapper
            //TODO: Implement this
        } else {
            // If the pool is not in damped state, we can give the delta to the swapper
            poolManager.take(
                currency,
                msg.sender,
                uint256(int256(hookDeltaUnspecified))
            );
        }

        return (this.afterSwap.selector, hookDeltaUnspecified);
    }

/*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/


/*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/

}