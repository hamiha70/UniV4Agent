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
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // 0. Decompose the delta
        int128 amountSpecified = delta.amount0();
        int128 amountUnspecified = delta.amount1();
        // 1. Check if the conditions for a normal undamped swap are met
        if (
            !s_isDampedPool[key.toId()] ||  // 
            params.zeroForOne != s_directionZeroForOne[key.toId()] ||
            amountSpecified >= 0 == s_directionZeroForOne[key.toId()]     // damped afterswap needed only when the amountSpecified is negative
            ) {
            console2.log("=== UNDAMPED SWAP ===");
            logInt256("params.amountSpecified", params.amountSpecified);
            logInt128("delta.amount0()", delta.amount0());
            logInt128("delta.amount1()", delta.amount1());
            emit SwapAtPoolPrice(key.toId(), amountUnspecified, params.zeroForOne);
            return (this.afterSwap.selector, 0);
        }

        console2.log("=== DAMPED SWAP ===");
        logInt256("params.amountSpecified", params.amountSpecified);
        logInt128("delta.amount0()", delta.amount0());
        logInt128("delta.amount1()", delta.amount1());

        // 2. Retrieve and calculate the price for the pool damped and undamped
        uint256 dampedSqrtPriceX96 = getDampedSqrtPriceX96(key.toId());
        console2.log("=== SQRT PRICES ===");
        console2.log("Damped sqrt price X96:", dampedSqrtPriceX96);

        // First shift right by 48 to prevent overflow when squaring
        uint256 shiftedPrice = uint256(dampedSqrtPriceX96) >> 48;
        console2.log("Shifted sqrt price:", shiftedPrice);

        // Square the price
        uint256 dampedPriceX96 = shiftedPrice * shiftedPrice ;
        console2.log("=== PRICES ===");
        console2.log("Damped price:", dampedPriceX96);

        // Convert to signed after all calculations
        console2.log("=== PRICE CONVERSION ===");
        console2.log("Amount specified:", amountSpecified);

        // Perform multiplication in int256
        int256 result = (int256(amountSpecified) * int256(dampedPriceX96)) / (1 << 96);
        console2.log("=== RESULT ===");
        console2.log("Result:", result);

        require(result >= type(int128).min && result <= type(int128).max, "Price calculation overflow");
        // Negate result like in calculateSwapReturnSimplified_Undamped
        int128 swapperAmount1 = -int128(result);
        int128 hookAmount1 = amountUnspecified - swapperAmount1;

        console2.log("=== FINAL AMOUNTS ===");
        console2.log("Swapper amount1:", swapperAmount1);
        console2.log("Hook amount1:", hookAmount1);

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
        logInt128("Amount unspecified", amountUnspecified);
        console2.log("=== DAMPED SWAP ===");
        console2.log("Damped priceX96:", dampedSqrtPriceX96);
        console2.log("Pool priceX96:", (getCurrentSqrtPriceX96(key.toId())) >> 48 * (getCurrentSqrtPriceX96(key.toId())) >> 48);
        logInt128("Swapper amount1", swapperAmount1);
        logInt128("Hook amount1", hookAmount1);
        console2.log("Specified currency index:", _nameSpecifiedCurrency(params));
        /*//////////////////////////////////////////////////////////////
                           END LOGGING FOR TESTING
        //////////////////////////////////////////////////////////////*/

        // 4. Emit the event
        emit SwapAtDampedPrice(key.toId(), swapperAmount1, hookAmount1, dampedSqrtPriceX96, getCurrentSqrtPriceX96(key.toId()), params.zeroForOne);

        // Determine which currency to use based on swap direction
        Currency currencyToUse;
        if (params.zeroForOne) {
            currencyToUse = key.currency0;  // For ZeroForOne exact output
        } else {
            currencyToUse = key.currency1;  // For OneForZero exact output
        }

        // Take hook's portion using _settleOrTake with correct currency
        _settleOrTake(currencyToUse, hookAmount1);

        // Return the hook's portion as delta (what we handled)
        return (this.afterSwap.selector, hookAmount1);
    }

/*//////////////////////////////////////////////////////////////
                           PUBLIC & EXTERNAL FUNCTIONS
//////////////////////////////////////////////////////////////*/
    
    function calculateSwapReturnSimplified_Undamped(
        int128 amountSpecified,
        PoolKey calldata key
    ) public view returns (int128 amountUnspecified) {
        uint256 priceX96 = calculateApproximatePoolPriceX96(key);
        // First shift price right to avoid overflow
        // Convert to signed after division to maintain precision
        int256 signedPrice = int256(uint256(priceX96));
        // Perform multiplication in int256 to avoid overflow
        int256 result = (int256(amountSpecified) * signedPrice) / (1 << 96);
        // Convert back to int128 with check
        require(result >= type(int128).min && result <= type(int128).max, "Price calculation overflow");
        return -int128(result);
    }

    // This function is used to calculate the swap return simplified based on the pool's current state BEFORE the swap has executed
    // It DOES NOT take into account the slippage
    // It DOES take into account the fee
    // It is NOT USED to calculate the swap return for the swapper and the hook in the damped state because it is an approximation
    function calculateSwapReturnSimplified_PotentiallyDamped(
        PoolKey calldata key,
        int128 amountSpecified
    ) public view returns (int128 amountOut) {
        uint160 dampedSqrtPriceX96 = getDampedSqrtPriceX96(key.toId());
        if (s_isDampedPool[key.toId()] && s_directionZeroForOne[key.toId()]) {
            uint256 ratioX96 = uint256(dampedSqrtPriceX96) * (1 << 96) / uint256(getCurrentSqrtPriceX96(key.toId()));
            int256 result = (int256(amountSpecified) * int256(uint256(ratioX96))) / (1 << 96);
            require(result >= type(int128).min && result <= type(int128).max, "Ratio calculation overflow");
            return int128(result);
        } else {
            return calculateSwapReturnSimplified_Undamped(amountSpecified, key);
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

    // @dev for beforeswap, we can calculate the approximate undamped pool price from the balance delta
    // @dev this is the price that the swapper will see before the swap when the pool is not damped
    // @dev The price is multiplied by 2^192 to get the price in full precision and comparable to sqrtPriceX96
    function calculateApproximatePoolPriceX96(PoolKey calldata key) internal view returns (uint256) {
        uint160 sqrtPriceX96 = getCurrentSqrtPriceX96(key.toId());
        uint24 fee = getCurrentFee(key.toId());
        
        // First shift right by 48 to prevent overflow when squaring
        uint256 shiftedPrice = uint256(sqrtPriceX96) >> 48;
        // Square the price
        uint256 squaredPrice = shiftedPrice * shiftedPrice;
        // Shift back by 96 (not 192 since we shifted right by 48*2=96 before)
        // Apply fee adjustment last
        return (squaredPrice * (1_000_000_000 - fee)) / 1_000_000_000;
    }

    // @dev for afterswap, we can calculate the effective undamped pool price from the balance delta
    // @dev this is the price that the swapper will see after the swap when the pool is not damped
    // @dev The price is multiplied by 2^192 to get the price in full precision and comparable to sqrtPriceX96
    function calculateEffectivePoolPriceX192FromBalanceDelta_Afterswap(BalanceDelta delta) internal pure returns (uint256) {
        uint256 amount1Abs = uint256(uint128(delta.amount1() >= 0 ? delta.amount1() : -delta.amount1()));
        uint256 amount0Abs = uint256(uint128(delta.amount0() >= 0 ? delta.amount0() : -delta.amount0()));
        return ((amount1Abs << 96) / amount0Abs) << 96;
    }

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
        console2.log("=== SETTLE OR TAKE ===");
        console2.log("Delta:", delta);
        // positive delta means hook should take tokens (getting tokens from pool)
        // negative delta means hook should settle tokens (giving tokens to pool)
        if (delta > 0) {
            console2.log("Taking tokens:", uint128(delta));
            currency.take(poolManager, address(this), uint128(delta), false);
        } else {
            console2.log("Settling tokens:", uint128(-delta));
            currency.settle(poolManager, address(this), uint128(-delta), false);
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

    function resetDampedPool(PoolId id) public onlyAuthorizedAgent {
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
    error AgentHook_DampedPoolPriceTooHigh(PoolId id, uint256 poolPriceX192, uint256 dampedPriceX192);
    error AgentHook_DampedPoolPriceTooLow(PoolId id, uint256 poolPriceX192, uint256 dampedPriceX192);
    error AgentHook_SwapAmountTooLarge(PoolId id, uint160 poolSqrtPriceX96, uint160 dampedSqrtPriceX96, int128 hookTokenOut, int128 swapperTokenOut);
/*//////////////////////////////////////////////////////////////
                           EVENTS
//////////////////////////////////////////////////////////////*/

    event HookOwnerSet(address indexed hookOwner);      
    event AuthorizedAgentSet(address indexed agent, bool authorized);
    event DampedPoolSet(PoolId indexed id, uint160 dampedPriceX96, bool directionZeroForOne);
    event DampedPoolReset(PoolId indexed id);
    event DampedSqrtPriceX96Set(PoolId indexed id, uint160 sqrtPriceX96);
    event PoolRegistered(PoolKey key);
    event SwapAtPoolPrice(PoolId indexed id, int128 swapperTokenOut, bool zeroForOne);
    event SwapAtDampedPrice(PoolId indexed id, int128 swapperTokenOut, int128 hookTokenOut, uint256 dampedPriceX96, uint256 poolPriceX96, bool zeroForOne);


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
