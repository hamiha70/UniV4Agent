# USDC Volume Agent

## Overview

The **USDC Volume Agent** is a Python-based monitoring tool that tracks **USDC (USD Coin) transfer volume** on the Ethereum blockchain. It connects to the Ethereum network via an RPC provider, fetches transfer events, and calculates the total volume of USDC transfers within a rolling 1-minute window. Additionally, it integrates with the Coinbase API for potential future functionality.

## Features

- Connects to an Ethereum node via **Alchemy RPC**.
- Fetches **USDC transfer events** from the last 10 blocks.
- Decodes transfer data (sender, receiver, and amount) and tracks it.
- Maintains a rolling **1-minute window** of transfer events.
- Displays real-time **USDC transfer volume**.
- Integrates with the **Coinbase API** for account interactions.

---

## Requirements

Ensure you have **Python 3.8+** installed. You also need **pip** to install dependencies.

### Dependencies

The required Python packages are listed in `requirements.txt`:

```bash
web3==6.15.1
python-dotenv==1.0.0
coinbase==2.1.0
eth-utils==2.3.1
eth-typing==3.5.2
```

### Environment Variables

Create a `.env` file in the project root and add the following credentials:

```ini
CDP_API_KEY_NAME=your_coinbase_api_key
CDP_API_KEY_PRIVATE_KEY=your_coinbase_private_key
OPENAI_API_KEY=your_openai_api_key
NETWORK_ID=base-sepolia
ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-alchemy-api-key
```

**Note:** Replace the placeholders with actual values.

---

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/Arbiter09/USDC-Volume-Agent.git
   cd usdc-volume-agent
   ```

2. Create and activate a virtual environment:

   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows use: venv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

---

## Usage

To start the USDC Volume Agent, run:

```bash
python main.py
```

The agent will:

- Connect to the Ethereum network.
- Fetch and decode USDC transfer events.
- Maintain a rolling 1-minute event window.
- Display real-time USDC volume updates.

### Expected Output

```bash
USDC Volume Agent Started...
Monitoring USDC transfers on Ethereum mainnet...
Fetching transfers from block 19000000 to 19000010
Found 5 transfer events
Time: 12:34:56 | 1-Min USDC Transfer Volume: 120.50 USDC | Events in window: 5
```

---

## Code Structure

- `main.py`: The core script that initializes the agent and fetches USDC transfers.
- `requirements.txt`: Contains necessary Python dependencies.
- `.env`: Stores API keys and RPC configurations (should not be committed to Git).

---

## Troubleshooting

### 1. `ERROR: ETHEREUM_RPC_URL not found in environment variables`

Ensure you have set up the `.env` file correctly and included `ETHEREUM_RPC_URL`.

### 2. `Failed to initialize Coinbase client`

Check that your `CDP_API_KEY_NAME` and `CDP_API_KEY_PRIVATE_KEY` are correct.

### 3. `Error fetching USDC transfers`

- Ensure that your Ethereum RPC URL is working.
- Try increasing the block range in `fetch_usdc_transfers`.

---

## License

This project is licensed under the **MIT License**.

---
