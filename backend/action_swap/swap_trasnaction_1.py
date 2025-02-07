from web3.middleware import geth_poa_middleware

# Connect to RPC
WEB3_PROVIDER_URL = os.getenv("ETHEREUM_RPC_URL")
web3 = Web3(Web3.HTTPProvider(WEB3_PROVIDER_URL))

# Required for networks like Base or Polygon
web3.middleware_onion.inject(geth_poa_middleware, layer=0)

# Uniswap V3 Router Contract ABI (SwapExactETHForTokens)
router_abi = '[{"inputs":[{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"name":"swapExactETHForTokens","outputs":[{"name":"","type":"uint256[]"}],"stateMutability":"payable","type":"function"}]'

# Load Router Contract
uniswap_router = web3.eth.contract(address=UNISWAP_ROUTER, abi=router_abi)

# Build transaction
tx = uniswap_router.functions.swapExactETHForTokens(
    amount_out_min,
    [ETH_ADDRESS, USDC_ADDRESS],  # Path from ETH to USDC
    wallet_provider.address,  # Your wallet receiving USDC
    deadline
).build_transaction({
    "from": wallet_provider.address,
    "value": amount_in_wei,  # Amount of ETH to swap
    "gas": 200000,  # Adjust based on estimation
    "gasPrice": web3.eth.gas_price,
    "nonce": web3.eth.get_transaction_count(wallet_provider.address),
})

# Sign and Send the transaction
signed_tx = web3.eth.account.sign_transaction(tx, private_key=wallet_provider.private_key)
tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)

print(f"Swap Executed! TX Hash: {tx_hash.hex()}")
