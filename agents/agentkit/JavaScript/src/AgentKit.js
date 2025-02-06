require("dotenv").config();

console.log("ETHEREUM_RPC_URL:", process.env.ETHEREUM_RPC_URL);
console.log("CDP_API_KEY_NAME:", process.env.CDP_API_KEY_NAME);
console.log(
  "CDP_API_KEY_PRIVATE_KEY:",
  process.env.CDP_API_KEY_PRIVATE_KEY ? "Loaded" : "Missing"
);

const {
  AgentKit,
  CdpWalletProvider,
  erc20ActionProvider,
  cdpApiActionProvider,
  cdpWalletActionProvider,
} = require("@coinbase/agentkit");
const Web3 = require("web3");
const { ethers } = require("ethers");

const USDC_CONTRACT_ADDRESS = Web3.utils.toChecksumAddress(
  "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eb48"
);
const USDC_TRANSFER_EVENT_SIGNATURE = ethers.keccak256(
  ethers.toUtf8Bytes("Transfer(address,address,uint256)")
);

if (!process.env.ETHEREUM_RPC_URL) {
  console.error("ERROR: ETHEREUM_RPC_URL not found in environment variables");
  process.exit(1);
}

const RPC_URL = process.env.ETHEREUM_RPC_URL;
let web3;
try {
  web3 = new Web3(new Web3.providers.HttpProvider(RPC_URL));
} catch (error) {
  console.error("Failed to initialize Web3:", error);
  process.exit(1);
}

class USDCVolumeAgent {
  constructor() {
    this.agent = null;
    this.transferEvents = [];
    this.isConnected = false;
  }

  async checkConnection() {
    try {
      await web3.eth.net.isListening();
      if (!this.isConnected) {
        console.log("Successfully connected to Ethereum network");
        this.isConnected = true;
      }
      return true;
    } catch (error) {
      console.error("Network connection error:", error.message);
      this.isConnected = false;
      return false;
    }
  }

  async initializeAgent() {
    const config = {
      apiKeyName: process.env.CDP_API_KEY_NAME,
      apiKeyPrivateKey: process.env.CDP_API_KEY_PRIVATE_KEY?.replace(
        /\\n/g,
        "\n"
      ),
      networkId: "ethereum-mainnet",
    };

    try {
      const walletProvider = await CdpWalletProvider.configureWithWallet(
        config
      );
      this.agent = await AgentKit.from({
        walletProvider,
        actionProviders: [
          erc20ActionProvider(),
          cdpApiActionProvider(config),
          cdpWalletActionProvider(config),
        ],
      });
      console.log("Agent initialized successfully");
    } catch (error) {
      console.error("Failed to initialize agent:", error);
      process.exit(1);
    }
  }

  async fetchUSDCTransfers() {
    if (!(await this.checkConnection())) {
      return;
    }

    try {
      const latestBlock = await web3.eth.getBlockNumber();
      const fromBlock = latestBlock - 10;

      console.log(
        `Fetching transfers from block ${fromBlock} to ${latestBlock}`
      );

      const logs = await web3.eth.getPastLogs({
        fromBlock: `0x${fromBlock.toString(16)}`,
        toBlock: "latest",
        address: USDC_CONTRACT_ADDRESS,
        topics: [USDC_TRANSFER_EVENT_SIGNATURE],
      });

      console.log(`Found ${logs.length} transfer events`);

      const currentTime = Date.now();

      for (const log of logs) {
        try {
          const from = `0x${log.topics[1].slice(26)}`;
          const to = `0x${log.topics[2].slice(26)}`;
          const amount = web3.eth.abi.decodeParameter("uint256", log.data);

          this.transferEvents.push({
            from: Web3.utils.toChecksumAddress(from),
            to: Web3.utils.toChecksumAddress(to),
            amount: parseFloat(ethers.formatUnits(amount, 6)),
            timestamp: currentTime,
            blockNumber: log.blockNumber,
          });
        } catch (error) {
          console.error("Error decoding transfer event:", error);
          console.error("Problematic log:", log);
          continue;
        }
      }

      this.cleanOldEvents();
      this.calculateVolume();
    } catch (error) {
      console.error("Error fetching USDC transfers:", error);
      console.error("Error details:", error.stack);
    }
  }

  cleanOldEvents() {
    const oneMinuteAgo = Date.now() - 60000;
    const oldCount = this.transferEvents.length;
    this.transferEvents = this.transferEvents.filter(
      (event) => event.timestamp >= oneMinuteAgo
    );
    const newCount = this.transferEvents.length;
    if (oldCount !== newCount) {
      console.log(`Cleaned ${oldCount - newCount} old events`);
    }
  }

  calculateVolume() {
    const totalVolume = this.transferEvents.reduce(
      (acc, event) => acc + event.amount,
      0
    );
    console.log(
      `Time: ${new Date().toLocaleTimeString()} | 1-Min USDC Transfer Volume: ${totalVolume.toFixed(
        2
      )} USDC | Events in window: ${this.transferEvents.length}`
    );
  }

  async start() {
    await this.initializeAgent();
    console.log("USDC Volume Agent Started...");
    console.log("Monitoring USDC transfers on Ethereum mainnet...");

    await this.fetchUSDCTransfers();

    setInterval(() => this.fetchUSDCTransfers(), 60000);
  }
}

const agent = new USDCVolumeAgent();
agent.start();
