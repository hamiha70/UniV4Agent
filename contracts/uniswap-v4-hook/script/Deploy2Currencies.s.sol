// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {AgentHook} from "../src/AgentHook.sol";
import {CurrencyCloneMiner} from "../src/utils/CurrencyCloneMiner.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "@uniswap/v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract Deploy2Currencies is Script, Test {

    function run() external returns (MockERC20 usdc_clone, MockERC20 eth_clone) {
        HelperConfig helperConfig = new HelperConfig();

        (/*address poolManagerAddress*/,
        /*address hookAddress*/,
        /*address hookOwnerAndDeployerAddress*/,
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
        /*address sETHAddress*/,
        /*address sUSDCAddress*/
        ) = helperConfig.activeNetworkConfig();
        
        console.log("Finding addresses for USDC and ETH clones on chainid:", block.chainid);
        /*********************************************************/
        // Running the CurrencyCloneMiner
        /*********************************************************/
        (address usdc_clone_address, address eth_clone_address, bytes32 salt_0, bytes32 salt_1) = CurrencyCloneMiner.find(
            create2DeployerAddress,
            type(MockERC20).creationCode,
            abi.encode("synthetic ETH", "ETH", 18),
            abi.encode("synthetic USDC", "USDC", 18)
            );
        /*********************************************************/
        console.log("Mined usdc clone address:", usdc_clone_address);
        console.log("Mined eth clone address:", eth_clone_address);
        console.log("Salt for eth clone:", uint256(salt_0));
        console.log("Salt for usdc clone:", uint256(salt_1));
        vm.startBroadcast(hookOwnerAndDeployerPrivateKey);
        eth_clone = new MockERC20{salt: salt_0}("synthetic ETH", "ETH", 18);
        usdc_clone = new MockERC20{salt: salt_1}("synthetic USDC", "USDC", 18);
        vm.stopBroadcast();
        console.log("Deployed eth clone address:", address(eth_clone));
        console.log("Deployed usdc clone address:", address(usdc_clone));
        require(address(eth_clone) == eth_clone_address, "Deployed address doesn't match mined address");
        require(address(usdc_clone) == usdc_clone_address, "Deployed address doesn't match mined address");
        /*********************************************************/
        // Verify the hook address matches the mined address
        console.log("Eth clone deployed at", address(eth_clone));
        console.log("Usdc clone deployed at", address(usdc_clone));
        assertGt(uint160(address(usdc_clone)), uint160(address(eth_clone)), "Usdc clone address is not greater than eth clone address");
        console.log("Usdc clone address is greater than eth clone address");

        return (usdc_clone, eth_clone);
    }
}
