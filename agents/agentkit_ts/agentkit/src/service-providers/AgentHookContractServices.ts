import { type EvmWalletProvider } from "../wallet-providers/evmWalletProvider";
import { type Address } from "viem";

// This service is used to interact with an AgentHook contract
// Read functions
// - poolManager()
// - getHookOwner()
// - getPoolManager()
// - getDampedSqrtPriceX96(PoolId id)
// - isDampedPool(PoolId id)
// - isRegisteredPool(PoolId id)
// - isAuthorizedAgent(address agent)
// - getCurrentSqrtPriceX96TickAndFees(PoolId id)
// - getCurrentSqrtPriceX96(PoolId id)
// - getCurrentDirectionZeroForOne(PoolId id)
// - getCurrentFee(PoolId id)
// - getPoolKey(PoolId)

// Write functions
// -setAuthorizedAgent(address agent, bool authorized)
// -setDampedSqrtPriceX96(PoolId, uint160)
// -setIsDampedPool(PoolId, bool)
// -setIsRegisteredPool(PoolId, bool)
// -setIsAuthorizedAgent(address, bool)

// Contract ABIs
const HOOK_ABIs = {
  getPoolManager: {
    inputs: [],
    name: "poolManager",
    outputs: [{ type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  getHookOwner: {
    inputs: [],
    name: "getHookOwner",
    outputs: [{ type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  getPoolKey: {
    inputs: [{ type: "bytes32" }],
    name: "getPoolKey",
    outputs: [{ type: "struct PoolKey" }],
    stateMutability: "view",
    type: "function",
  },
  setAuthorizedAgent: {
    inputs: [{ type: "address" }, { type: "bool" }],
    name: "setAuthorizedAgent",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  setDampedSqrtPriceX96: {
    inputs: [{ type: "bytes32" }, { type: "uint160" }],
    name: "setDampedSqrtPriceX96",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
};

export class AgentHookContractServices {
  private walletProvider: EvmWalletProvider;

  constructor(walletProvider: EvmWalletProvider) {
    this.walletProvider = walletProvider;
  }

  async readPoolManager(hookAddress: Address): Promise<Address> {
    const result = await this.walletProvider.readContract({
      address: hookAddress,
      abi: [HOOK_ABIs.getPoolManager],
      functionName: "poolManager",
    });

    return result as Address;
  }

  async setAuthorizedAgent(
    hookAddress: Address,
    agent: Address,
    authorized: boolean,
  ): Promise<`0x${string}`> {
    return await this.walletProvider.sendTransaction({
      to: hookAddress,
      data: {
        abi: [HOOK_ABIs.setAuthorizedAgent],
        functionName: "setAuthorizedAgent",
        args: [agent, authorized],
      },
    });
  }
}
