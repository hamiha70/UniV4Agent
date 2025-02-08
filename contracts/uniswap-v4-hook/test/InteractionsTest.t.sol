// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {MockERC20} from "@uniswap/v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

import {SetAuthorizedAgent} from "../script/Interactions.s.sol";

import {AgentHook} from "../src/AgentHook.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";


contract InteractionsTest is StdCheats, Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolId;

    uint256 public INITIAL_USDC_MINT = 1000 ether;
// Smart Contracts for hook and pool manager    
    AgentHook public agentHook;
    HelperConfig public helperConfig;
    IPoolManager public poolManager;
    PoolSwapTest public poolSwapTest;
    PoolModifyLiquidityTest public poolModifyLiquidityTest;
// ERC20 tokens and currencies
    MockERC20 public USDC;
    MockERC20 public LINK;
    Currency public currency0;   // USDC
    Currency public currency1;   // LINK

// Private keys for hook owner and agent
    uint256 public hookOwnerAndDeployerPrivateKey;
    uint256 public agentPrivateKey;
    uint256 public swapperPrivateKey;
    uint256 public liquidityProviderPrivateKey;

// Addresses for hook owner and agent and other actors
    address public hookOwner;
    address public agent;
    address public swapper;
    address public liquidityProvider;


    constructor() {
        helperConfig = new HelperConfig();
        (address _poolManagerAddress,
        address _hookAddress,
        address _hookOwnerAndDeployerAddress,
        uint256 _hookOwnerAndDeployerPrivateKey,
        address _poolSwapTestAddress,   
        address _poolModifyLiquidityTestAddress,
        /*address _create2DeployerAddress*/,
        address _agentAddress,
        uint256 _agentPrivateKey,
        address _swapperAddress,
        uint256 _swapperPrivateKey,
        address _liquidityProviderAddress,
        uint256 _liquidityProviderPrivateKey,
        address _USDCAddress,
        address _LINKAddress) = helperConfig.activeNetworkConfig();

    // Pool Manager and Hook
        poolManager = IPoolManager(_poolManagerAddress);
        agentHook = AgentHook(_hookAddress);
    // Pool Swap Test and Pool Modify Liquidity Test
        poolSwapTest = PoolSwapTest(_poolSwapTestAddress);
        poolModifyLiquidityTest = PoolModifyLiquidityTest(_poolModifyLiquidityTestAddress);
    // ERC20 tokens
        USDC = MockERC20(_USDCAddress);
        LINK = MockERC20(_LINKAddress);
    // Currencies
        currency0 = Currency.wrap(_USDCAddress);
        currency1 = Currency.wrap(_LINKAddress);
    // Addresses
        hookOwner = _hookOwnerAndDeployerAddress;
        agent = _agentAddress;
        swapper = _swapperAddress;
        liquidityProvider = _liquidityProviderAddress;
    // Private keys
        hookOwnerAndDeployerPrivateKey = _hookOwnerAndDeployerPrivateKey;
        agentPrivateKey = _agentPrivateKey;
        swapperPrivateKey = _swapperPrivateKey;
        liquidityProviderPrivateKey = _liquidityProviderPrivateKey;
    }

    function setUp() public {

        //  mint USDC tokens
        USDC.mint(swapper, INITIAL_USDC_MINT);
        USDC.mint(liquidityProvider, INITIAL_USDC_MINT);



    }


    function testSetAuthorizedAgent() public {
        SetAuthorizedAgent setAuthorizedAgent = new SetAuthorizedAgent();
        setAuthorizedAgent.setAuthorizedAgent(true);
    }
}
