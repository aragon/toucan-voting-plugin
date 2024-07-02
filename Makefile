# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# env var check
check-env :; echo $(ETHERSCAN_API_KEY)

# linux: allow shell scripts to be executed
allow-scripts:; chmod +x script/bash/*.sh

# create an HTML coverage report in ./report (requires lcov & genhtml)
coverage-report:; ./script/bash/coverage-report.sh

# init the repo
install :; make allow-scripts && make coverage-report

# run deploy script but don't broadcast the transaction
preview-deploy-arbitrum-sepolia:; export EXECUTION_OR_VOTING=EXECUTION && forge script DeployE2E \
	--rpc-url https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	-vvvvv

# deploy the contract to the arbitrum-sepolia network
deploy-arbitrum-sepolia:; export EXECUTION_OR_VOTING=EXECUTION && forge script DeployE2E \
	--rpc-url https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ARBISCAN_API_KEY) \
	-vvvvv

# run deploy script but don't broadcast the transaction
preview-deploy-optimism-sepolia:; export EXECUTION_OR_VOTING=VOTING && forge script DeployE2E \
	--rpc-url https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	-vvvvv

# deploy the contract to the optimism-sepolia network
deploy-optimism-sepolia:; export EXECUTION_OR_VOTING=VOTING && forge script DeployE2E \
	--rpc-url https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(OPTIMISM_API_KEY) \
	-vvvvv

