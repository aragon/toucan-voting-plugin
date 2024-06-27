# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# env var check
check-env :; echo $(ETHERSCAN_API_KEY)

allow-scripts:; chmod +x script/bash/*.sh

# create an HTML coverage report in ./report (requires lcov & genhtml)
coverage-report:; ./script/bash/coverage-report.sh

deploy-sepolia:; export EXECUTION_OR_VOTING=EXECUTION && forge script DeployToucan \
	--rpc-url https://sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvvvv

deploy-arbitrum-sepolia:; export EXECUTION_OR_VOTING=VOTING && forge script DeployToucan \
	--rpc-url https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ARBISCAN_API_KEY) \
	-vvvvv

script-sepolia :; export EXECUTION_OR_VOTING=EXECUTION && forge script ExecuteDemoOffsite \
	--rpc-url https://sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	-vvv

script-arbitrum-sepolia :; export EXECUTION_OR_VOTING=VOTING && forge script ExecuteDemoOffsite \
	--rpc-url https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	-vvv