# Include .env file
-include .env

# Phony targets (not associated with files)
.PHONY: all install update build test clean deploy-sepolia deploy-mainnet format help

# Default target
all: clean install update build test

# Install project dependencies
install:
	forge install foundry-rs/forge-std --no-commit
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install smartcontractkit/foundry-chainlink-toolkit --no-commit

# Update dependencies
update:
	forge update

# Build the project
build:
	forge build

# Run tests
test:
	forge test

# Run tests with gas report
test-with-gas:
	forge test --gas-report

# Clean the build artifacts
clean:
	forge clean

# Deploy to Sepolia testnet
deploy-sepolia:
	forge script script/MeliesScript.s.sol:MeliesScript \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--broadcast \
		--verify \
		-vvvv

# Deploy to Ethereum mainnet
deploy-mainnet:
	forge script script/MeliesScript.s.sol:MeliesScript \
		--rpc-url $(MAINNET_RPC_URL) \
		--broadcast \
		--verify \
		-vvvv

# Format code
format:
	forge fmt

# Generate documentation
docs:
	forge doc

# Help command to list available targets
help:
	@echo "Available targets:"
	@echo "  install         - Install Foundry and project dependencies"
	@echo "  update          - Update dependencies"
	@echo "  build           - Build the project"
	@echo "  test            - Run tests"
	@echo "  test-with-gas   - Run tests with gas report"
	@echo "  clean           - Clean build artifacts"
	@echo "  deploy-sepolia  - Deploy to Sepolia testnet"
	@echo "  deploy-mainnet  - Deploy to Ethereum mainnet"
	@echo "  format          - Format code"
	@echo "  docs            - Generate documentation"
	@echo "  all             - Run clean, install, update, build, and test"
	@echo "  help            - Show this help message"