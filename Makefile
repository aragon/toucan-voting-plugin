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


send-tokens :; cast send 0xcD25DAecFe1334e1879580E1762d98E22D7ad50C \
	"transfer(address,uint256)" 0x8bF1e340055c7dE62F11229A149d3A1918de3d74 100ether \
	--rpc-url https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) 


bridge-tokens :; forge script BridgeAndSend \
	--rpc-url https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	-vvvvv

unstick-deploy-optimism-sepolia :; forge script UnstickDeploy \
	--rpc-url https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	-vvvvv

unstick-dispatch-arbitrum-sepolia :; forge test --mc ToucanReceiverStuckMessage \
	--rpc-url https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA) \
	-vvvvv

test-oapp-conf :; forge test --mc TestOAppConf \
	--rpc-url https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA) \
	-vvvvv

set-send-conf-arbitrum :; forge script SetOAppConf \
	--rpc-url https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	-vvvvv


## DEPLOY SCRIPTS

define deploy-script
	export STAGE=$(1) && \
	export EXECUTION_OR_VOTING=$(2) && \
	forge script DeployE2E \
		--rpc-url $(3) \
		--private-key $(PRIVATE_KEY) \
		$(4) \
		-vvvvv
endef

### Arbitrum ###



# run deploy script but don't broadcast the transaction
preview-deploy-arbitrum-sepolia-stage-0:
	$(call deploy-script,0,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-sepolia-stage-1:
	$(call deploy-script,1,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-sepolia-stage-2:
	$(call deploy-script,2,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-sepolia-stage-3:
	$(call deploy-script,3,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-sepolia-stage-4:
	$(call deploy-script,4,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),)

# deploy the contract to the arbitrum-sepolia network
deploy-arbitrum-sepolia-stage-0:
	$(call deploy-script,0,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-sepolia-stage-1:
	$(call deploy-script,1,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-sepolia-stage-2:
	$(call deploy-script,2,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-sepolia-stage-3:
	$(call deploy-script,3,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-sepolia-stage-4:
	$(call deploy-script,4,EXECUTION,https://arbitrum-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

### Optimism ###

# run deploy script but don't broadcast the transaction
preview-deploy-optimism-sepolia-stage-0:
	$(call deploy-script,0,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-optimism-sepolia-stage-1:
	$(call deploy-script,1,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-optimism-sepolia-stage-2:
	$(call deploy-script,2,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-optimism-sepolia-stage-3:
	$(call deploy-script,3,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-optimism-sepolia-stage-4:
	$(call deploy-script,4,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),)

# deploy the contract to the optimism-sepolia network
deploy-optimism-sepolia-stage-0:
	$(call deploy-script,0,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(OPTIMISM_API_KEY))

deploy-optimism-sepolia-stage-1:
	$(call deploy-script,1,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(OPTIMISM_API_KEY))

deploy-optimism-sepolia-stage-2:
	$(call deploy-script,2,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(OPTIMISM_API_KEY))

deploy-optimism-sepolia-stage-3:
	$(call deploy-script,3,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(OPTIMISM_API_KEY))

deploy-optimism-sepolia-stage-4:
	$(call deploy-script,4,VOTING,https://optimism-sepolia.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(OPTIMISM_API_KEY))



## Mainnet Arbitrum 

# run deploy script but don't broadcast the transaction
preview-deploy-arbitrum-stage-0:
	$(call deploy-script,0,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-stage-1:
	$(call deploy-script,1,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-stage-2:
	$(call deploy-script,2,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-stage-3:
	$(call deploy-script,3,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),)

preview-deploy-arbitrum-stage-4:
	$(call deploy-script,4,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),)

# deploy the contract to the arbitrum-mainnet network
deploy-arbitrum-stage-0:
	$(call deploy-script,0,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-stage-1:
	$(call deploy-script,1,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-stage-2:
	$(call deploy-script,2,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-stage-3:
	$(call deploy-script,3,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

deploy-arbitrum-stage-4:
	$(call deploy-script,4,EXECUTION,https://arbitrum-mainnet.infura.io/v3/$(API_KEY_INFURA),--broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY))

