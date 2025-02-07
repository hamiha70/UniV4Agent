-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil  deploy-anvil deploy-sepolia deploy-base deploy-base-sepolia verify-sepolia-mainnet-contract verify-base-sepolia-contract

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install \
    frin/foundry-devops@0.2.2 --no-commit && \
    forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit && \
    forge install foundry-rs/forge-std@v1.8.2 --no-commit && \
    forge install uniswap/v4-core@1.0.2 --no-commit && \
    forge install uniswap/v4-periphery@1.0.0 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

deploy-anvil:
	@forge script script/DeployFundMe.s.sol:DeployFundMe --rpc-url chttp://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-sepolia-mainnet:
	@forge script script/DeployHook.s.sol:DeployHook --rpc-url $(ETHEREUM_SEPOLIA_RPC_URL) --private-key $(SEPOLIA_ACCOUNT_PRIVATE_KEY_1) --broadcast -vvvv --verify --etherscan-api-key $(ETHERSCAN_API_KEY)


deploy-sepolia-base:
	@forge script script/DeployHook.s.sol:DeployHook --rpc-url $(BASE_SEPOLIA_RPC_URL) --private-key $(SEPOLIA_ACCOUNT_PRIVATE_KEY_1) --broadcast -vvvv --verify --etherscan-api-key $(ETHERSCAN_BASE_API_KEY)


verify-sepolia-mainnet-contract:
	@forge verify-contract --chain 11155111 \
	--num-of-optimizations $(NUMBER_OF_OPTIMIZATIONS) \
	--watch \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	--constructor-args $(shell cast abi-encode "constructor(address,address)" "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543" "0x36AB88fDd34848C0caF4599736a9D3a860D051Ba") \
	$(SEPOLIA_MAINNET_DEPLOYED_HOOK_ADDRESS) \
	src/AgentHook.sol:AgentHook

verify-base-sepolia-contract:
	@forge verify-contract --chain 84532 \
	--num-of-optimizations $(NUMBER_OF_OPTIMIZATIONS) \
	--watch \
	--etherscan-api-key $(ETHERSCAN_BASE_API_KEY) \
	--constructor-args $(shell cast abi-encode "constructor(address,address)" "0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408" "0x36AB88fDd34848C0caF4599736a9D3a860D051Ba") \
	$(BASE_SEPOLIA_DEPLOYED_HOOK_ADDRESS) \
	src/AgentHook.sol:AgentHook

fork-deploy-sepolia-mainnet:
	@forge script script/DeployHook.s.sol:DeployHook --fork-url $(ETHEREUM_SEPOLIA_RPC_URL) --private-key $(SEPOLIA_ACCOUNT_PRIVATE_KEY_1) --fork


fork-deploy-sepolia-base:
	@forge script script/DeployHook.s.sol:DeployHook --fork-url $(BASE_SEPOLIA_RPC_URL) --private-key $(SEPOLIA_ACCOUNT_PRIVATE_KEY_1) --fork