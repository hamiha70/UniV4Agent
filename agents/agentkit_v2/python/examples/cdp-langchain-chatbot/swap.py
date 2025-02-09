from web3.middleware import geth_poa_middleware

# Connect to RPC
WEB3_PROVIDER_URL = os.getenv("ETHEREUM_RPC_URL")
web3 = Web3(Web3.HTTPProvider(WEB3_PROVIDER_URL))

# Required for networks like Base or Polygon
web3.middleware_onion.inject(geth_poa_middleware, layer=0)

# Uniswap V4 Router Contract ABI ( PoolSwapTest.sol)
router_abi = '[{"inputs":[{"internalType":"contract IPoolManager","name":"_manager","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[],"name":"NoSwapOccurred","type":"error"},{"inputs":[],"name":"manager","outputs":[{"internalType":"contract IPoolManager","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"components":[{"internalType":"Currency","name":"currency0","type":"address"},{"internalType":"Currency","name":"currency1","type":"address"},{"internalType":"uint24","name":"fee","type":"uint24"},{"internalType":"int24","name":"tickSpacing","type":"int24"},{"internalType":"contract IHooks","name":"hooks","type":"address"}],"internalType":"struct PoolKey","name":"key","type":"tuple"},{"components":[{"internalType":"bool","name":"zeroForOne","type":"bool"},{"internalType":"int256","name":"amountSpecified","type":"int256"},{"internalType":"uint160","name":"sqrtPriceLimitX96","type":"uint160"}],"internalType":"struct IPoolManager.SwapParams","name":"params","type":"tuple"},{"components":[{"internalType":"bool","name":"takeClaims","type":"bool"},{"internalType":"bool","name":"settleUsingBurn","type":"bool"}],"internalType":"struct PoolSwapTest.TestSettings","name":"testSettings","type":"tuple"},{"internalType":"bytes","name":"hookData","type":"bytes"}],"name":"swap","outputs":[{"internalType":"BalanceDelta","name":"delta","type":"int256"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"bytes","name":"rawData","type":"bytes"}],"name":"unlockCallback","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"nonpayable","type":"function"}]'

# Load Router Contract
uniswap_router = web3.eth.contract(address=UNISWAP_ROUTER, abi=router_abi)

# Build transaction
tx = uniswap_router.functions.swap(
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
