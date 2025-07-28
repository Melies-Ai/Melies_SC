# Include .env file
-include .env

# Network RPC URLs (can be overridden via environment variables)
SEPOLIA_RPC_URL ?= https://sepolia.base.org
MAINNET_RPC_URL ?= https://mainnet.base.org

# Phony targets (not associated with files)
.PHONY: all install update build test clean deploy-sepolia deploy-mainnet format help test-with-gas test-coverage test-coverage-report

# Default target
all: clean install update build test

# Install project dependencies
install:
	forge install foundry-rs/forge-std --no-commit
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install smartcontractkit/foundry-chainlink-toolkit --no-commit
	git submodule add -f https://github.com/Uniswap/v2-periphery.git lib/uniswap-v2-periphery

# Update dependencies
update:
	forge update

# Build the project
build:
	forge build

# Run tests
test:
	forge test --no-match-test test_LargeAmountStakersScenario --ffi --gas-limit 156000000 --memory-limit 30000000000
	forge test --match-test test_LargeAmountStakersScenario --ffi --gas-limit 15600000000000000 --memory-limit 30000000000

# Run tests with gas report
test-with-gas:
	forge test --no-match-test test_LargeAmountStakersScenario --ffi --gas-limit 156000000 --memory-limit 30000000000 --gas-report

# Run test coverage (excluding resource-intensive tests)
test-coverage:
	forge coverage --no-match-test test_LargeAmountStakersScenario --ir-minimum --no-match-coverage "src/mock"

# Run test coverage with detailed report
test-coverage-report:
	forge coverage --no-match-test test_LargeAmountStakersScenario --report lcov --ir-minimum --no-match-coverage "src/mock"

# Clean the build artifacts
clean:
	forge clean

# Deploy to Sepolia testnet
deploy-sepolia:
	forge script script/MeliesTestnet.s.sol:MeliesTestnetScript \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--broadcast \
		--verify \
		-vvvv

# Deploy to Ethereum mainnet
deploy-mainnet:
	forge script script/Melies.s.sol:MeliesMainnetScript \
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
	@echo "  install                  - Install Foundry and project dependencies"
	@echo "  update                   - Update dependencies"
	@echo "  build                    - Build the project"
	@echo "  test                     - Run tests"
	@echo "  test-with-gas            - Run tests with gas report"
	@echo "  test-coverage            - Run test coverage (excludes heavy tests & mock contracts)"
	@echo "  test-coverage-report     - Generate LCOV coverage report (excludes mocks)"
	@echo "  clean                    - Clean build artifacts"
	@echo "  deploy-sepolia           - Deploy to Sepolia testnet"
	@echo "  deploy-mainnet           - Deploy to Ethereum mainnet"
	@echo "  format                   - Format code"
	@echo "  docs                     - Generate documentation"
	@echo "  all                      - Run clean, install, update, build, and test"
	@echo "  help                     - Show this help message"