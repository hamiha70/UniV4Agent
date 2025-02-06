# main.py
import os
import time
from datetime import datetime
from typing import List, Dict, Any
from decimal import Decimal
from dotenv import load_dotenv
from web3 import Web3
from eth_typing import ChecksumAddress
from requests.exceptions import ConnectionError
from eth_utils import to_checksum_address
from coinbase.wallet.client import Client as CoinbaseClient

# Load environment variables
load_dotenv()

# Constants
USDC_CONTRACT_ADDRESS = Web3.to_checksum_address("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eb48")
USDC_TRANSFER_EVENT_SIGNATURE = Web3.keccak(
    text="Transfer(address,address,uint256)"
).hex()

class USDCVolumeAgent:
    def __init__(self):
        self.rpc_url = os.getenv("ETHEREUM_RPC_URL")
        if not self.rpc_url:
            raise ValueError("ERROR: ETHEREUM_RPC_URL not found in environment variables")
        
        self.web3 = Web3(Web3.HTTPProvider(self.rpc_url))
        self.transfer_events: List[Dict[str, Any]] = []
        self.is_connected = False
        self.coinbase_client = None
        self._initialize_coinbase()

    def _initialize_coinbase(self):
        """Initialize Coinbase client with API credentials"""
        api_key = os.getenv("CDP_API_KEY_NAME")
        api_secret = os.getenv("CDP_API_KEY_PRIVATE_KEY")
        
        if not all([api_key, api_secret]):
            raise ValueError("Coinbase API credentials not found in environment variables")
        
        try:
            self.coinbase_client = CoinbaseClient(api_key, api_secret)
            print("Coinbase client initialized successfully")
        except Exception as e:
            print(f"Failed to initialize Coinbase client: {e}")
            raise

    async def check_connection(self) -> bool:
        """Check if connected to Ethereum network"""
        try:
            if self.web3.is_connected():
                if not self.is_connected:
                    print("Successfully connected to Ethereum network")
                    self.is_connected = True
                return True
            self.is_connected = False
            return False
        except ConnectionError as e:
            print(f"Network connection error: {e}")
            self.is_connected = False
            return False

    async def fetch_usdc_transfers(self):
        """Fetch USDC transfer events from recent blocks"""
        if not await self.check_connection():
            return

        try:
            latest_block = self.web3.eth.block_number
            from_block = latest_block - 10  # Last 10 blocks

            print(f"Fetching transfers from block {from_block} to {latest_block}")

            event_filter = {
                'fromBlock': hex(from_block),
                'toBlock': 'latest',
                'address': USDC_CONTRACT_ADDRESS,
                'topics': [USDC_TRANSFER_EVENT_SIGNATURE]
            }

            logs = self.web3.eth.get_logs(event_filter)
            print(f"Found {len(logs)} transfer events")

            current_time = time.time() * 1000  # Convert to milliseconds

            for log in logs:
                try:
                    # Decode Transfer event data
                    from_addr = to_checksum_address(f"0x{log['topics'][1].hex()[26:]}")
                    to_addr = to_checksum_address(f"0x{log['topics'][2].hex()[26:]}")
    # Fix the amount decoding
                    amount = int(log['data'].hex(), 16)
                    
                    # USDC has 6 decimals
                    decimal_amount = Decimal(amount) / Decimal(10 ** 6)

                    self.transfer_events.append({
                        'from': from_addr,
                        'to': to_addr,
                        'amount': float(decimal_amount),
                        'timestamp': current_time,
                        'blockNumber': log['blockNumber']
                    })
                except Exception as e:
                    print(f"Error decoding transfer event: {e}")
                    print(f"Problematic log: {log}")
                    continue

            self.clean_old_events()
            self.calculate_volume()

        except Exception as e:
            print(f"Error fetching USDC transfers: {e}")
            import traceback
            print(f"Error details: {traceback.format_exc()}")

    def clean_old_events(self):
        """Remove events older than 1 minute"""
        one_minute_ago = time.time() * 1000 - 60000
        old_count = len(self.transfer_events)
        self.transfer_events = [
            event for event in self.transfer_events 
            if event['timestamp'] >= one_minute_ago
        ]
        new_count = len(self.transfer_events)
        
        if old_count != new_count:
            print(f"Cleaned {old_count - new_count} old events")

    def calculate_volume(self):
        """Calculate and display total USDC transfer volume"""
        total_volume = sum(event['amount'] for event in self.transfer_events)
        current_time = datetime.now().strftime("%H:%M:%S")
        print(
            f"Time: {current_time} | "
            f"1-Min USDC Transfer Volume: {total_volume:.2f} USDC | "
            f"Events in window: {len(self.transfer_events)}"
        )

    async def start(self):
        """Start the USDC volume monitoring agent"""
        print("USDC Volume Agent Started...")
        print("Monitoring USDC transfers on Ethereum mainnet...")

        while True:
            await self.fetch_usdc_transfers()
            await asyncio.sleep(60)  # Wait for 60 seconds before next fetch

if __name__ == "__main__":
    import asyncio
    
    async def main():
        agent = USDCVolumeAgent()
        await agent.start()

    asyncio.run(main())