import { AgentHookContractServices } from "../../../agentkit/src/service-providers/AgentHookContractServices";
import { ViemWalletProvider } from "../../../agentkit/src/wallet-providers/viemWalletProvider";
import { createWalletClient, http } from "viem";
import dotenv from "dotenv";
import dotenvExpand from "dotenv-expand";
import path from "path";
import fs from "fs";

// Load and expand environment variables
const envPath = path.resolve(__dirname, "../../../../../env");

// Check if directory exists
if (!fs.existsSync(envPath)) {
  console.error(`Environment directory not found at: ${envPath}`);
  process.exit(1);
}

// Check each env file before loading
const envFiles = [
  ".env.local",
  ".env.agent",
  ".env.hook",
  ".env.uniswap.public",
];

envFiles.forEach((file) => {
  const filePath = path.join(envPath, file);
  if (!fs.existsSync(filePath)) {
    console.error(`Environment file not found: ${filePath}`);
    process.exit(1);
  }
});

const env1 = dotenv.config({ path: path.join(envPath, ".env.local") });
dotenvExpand.expand(env1);

const env2 = dotenv.config({ path: path.join(envPath, ".env.agent") });
dotenvExpand.expand(env2);

const env3 = dotenv.config({ path: path.join(envPath, ".env.hook") });
dotenvExpand.expand(env3);

const env4 = dotenv.config({ path: path.join(envPath, ".env.uniswap.public") });
dotenvExpand.expand(env4);

// Add debug logging
console.log("Environment path:", envPath);
console.log("Current working directory:", process.cwd());
console.log("Environment variables loaded:", {
  hookAddress: process.env.BASE_UNIV4_HOOK_ADDRESS,
  poolManager: process.env.BASE_UNIV4_POOL_MANAGER_ADDRESS,
  testPrivateKey: process.env.TEST_PRIVATE_KEY?.substring(0, 6) + "...",
  testAddress: process.env.TEST_ADDRESS,
  rpcUrl: process.env.RPC_URL,
});

console.log("Resolved env paths:", {
  directory: envPath,
  files: envFiles.map((file) => path.join(envPath, file)),
});

const hookAddress = process.env.BASE_UNIV4_HOOK_ADDRESS as `0x${string}`;
const poolManager = process.env
  .BASE_UNIV4_POOL_MANAGER_ADDRESS as `0x${string}`;

describe("AgentHook", () => {
  let contractService: AgentHookContractServices;
  let walletProvider: ViemWalletProvider;

  beforeEach(async () => {
    if (
      !process.env.TEST_PRIVATE_KEY ||
      !process.env.TEST_ADDRESS ||
      !process.env.RPC_URL
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
          default: { http: [process.env.RPC_URL] },
          public: { http: [process.env.RPC_URL] },
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
    const poolManagerFromHook = await contractService.readPoolManager(
      hookAddress
    );
    expect(poolManagerFromHook).toMatch(poolManager);
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
