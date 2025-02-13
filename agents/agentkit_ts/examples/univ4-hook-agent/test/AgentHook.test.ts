import { AgentHookContractServices } from "../../../agentkit/src/service-providers/AgentHookContractServices";
import { ViemWalletProvider } from "../../../agentkit/src/wallet-providers/viemWalletProvider";
import { createWalletClient, http } from "viem";
import dotenv from "dotenv";

// Load test environment variables
dotenv.config();

describe("AgentHook", () => {
  let contractService: AgentHookContractServices;
  let walletProvider: ViemWalletProvider;

  beforeEach(async () => {
    if (
      !process.env.TEST_PRIVATE_KEY ||
      !process.env.TEST_ADDRESS ||
      !process.env.BASE_SEPOLIA_RPC_URL
    ) {
      throw new Error("Required test environment variables are not set");
    }

    const configViemWalletProvider = {
      privateKey: process.env.TEST_PRIVATE_KEY as `0x${string}`,
      account: process.env.TEST_ADDRESS as `0x${string}`,
      chain: {
        id: 84532,
        name: "Base Sepolia",
        network: "base-sepolia",
        nativeCurrency: {
          name: "Ether",
          symbol: "ETH",
          decimals: 18,
        },
        rpcUrls: {
          default: { http: [process.env.BASE_SEPOLIA_RPC_URL] },
          public: { http: [process.env.BASE_SEPOLIA_RPC_URL] },
        },
      },
      transport: http(),
    };

    walletProvider = new ViemWalletProvider(
      createWalletClient(configViemWalletProvider)
    );
    contractService = new AgentHookContractServices(walletProvider);
  });

  it("should read pool manager address", async () => {
    const hookAddress =
      "0x1234567890123456789012345678901234567890" as `0x${string}`;
    const poolManager = await contractService.readPoolManager(hookAddress);
    expect(poolManager).toMatch(/^0x/);
  });

  it("should set authorized agent", async () => {
    const hookAddress =
      "0x1234567890123456789012345678901234567890" as `0x${string}`;
    const agentAddress =
      "0x2345678901234567890123456789012345678901" as `0x${string}`;
    const tx = await contractService.setAuthorizedAgent(
      hookAddress,
      agentAddress,
      true
    );
    expect(tx).toMatch(/^0x/);
  });
});
