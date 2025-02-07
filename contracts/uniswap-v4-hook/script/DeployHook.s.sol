// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AgentHook} from "../src/AgentHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "@uniswap/v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";

contract DeployHook is Script {
    address public constant HOOK_OWNER = address(0x1);
    address public constant POOL_MANAGER = address(0x2);

    function run() external returns (AgentHook agentHook, MockERC20 mockUSDC, MockERC20 mockLINK,  HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        (address poolManagerAddress,
        address hookOwnerAndDeployerAddress,
        uint256 hookOwnerAndDeployerPrivateKey,
        /*address poolSwapTestAddress*/, 
        /*address poolModifyLiquidityTestAddress*/,
        address create2DeployerAddress, 
        /*address agentAdress*/, 
        /*uint256 agentPrivateKey*/, 
        /*address swapperAddress*/, 
        /*uint256 swapperPrivateKey*/, 
        /*address liquidityProviderAddress*/, 
        /*uint256 liquidityProviderPrivateKey*/, 
        address USDCAddress, 
        address LINKAddress) = helperConfig.activeNetworkConfig();
        
        // Requires Mining an address that conforms to the flags
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG 
            // Hooks.BEFORE_SWAP_FLAG 
            // Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        // Use HookMiner to find a salt that will produce a hook address with the correct flags

        console.log("Running HookMiner for AgentHook on chainid:", block.chainid);
        /*********************************************************/
        // Running the HookMiner
        /*********************************************************/
        (address hookAddress, bytes32 salt) = HookMiner.find(
            create2DeployerAddress,
            flags,
            type(AgentHook).creationCode,
            abi.encode(poolManagerAddress, hookOwnerAndDeployerAddress)
        );
        /*********************************************************/
        console.log("Mined hook address:", hookAddress);
        console.log("Salt:", uint256(salt));
        vm.startBroadcast(hookOwnerAndDeployerPrivateKey);
        agentHook = new AgentHook{salt: salt}(IPoolManager(poolManagerAddress), hookOwnerAndDeployerAddress);
        vm.stopBroadcast();
        console.log("Deployed hook address:", address(agentHook));
        require(address(agentHook) == hookAddress, "Deployed address doesn't match mined address");
        /*********************************************************/
        // Verify the hook address matches the mined address
        console.log("AgentHook deployed at", address(agentHook));
        console.log("Expected flags:", flags);
        console.log("Actual flags:", uint160(uint256(uint160(address(agentHook)))));
        console.log("Hook address matches expected flags");

        // Initialize mock tokens
        mockUSDC = MockERC20(USDCAddress);
        mockLINK = MockERC20(LINKAddress);

        return (agentHook, mockUSDC, mockLINK, helperConfig);
    }
}
