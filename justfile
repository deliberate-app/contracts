# Show commands before running (helps debug failures)
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe
default:
    @just --list

# Install contract dependencies
deps:
    forge soldeer install

# Install test tooling (solhint, etc.)
tooling:
    bun install

# Clean contract dependencies
deps-clean:
    forge soldeer clean

# Clean build artifacts
clean:
    forge clean

# Build contracts
build *args:
    forge build {{ args }}

# Run tests
test *args:
    forge test {{ args }}

# Show coverage
coverage *args:
    forge coverage {{ args }}

# Lint (forge lint + solhint)
lint:
    forge lint --deny warnings
    bunx --bun solhint --config .solhint.json 'src/**/*.sol'
    bunx --bun solhint --config .solhint.other.json 'test/**/*.sol'
    bunx --bun solhint --config .solhint.other.json 'script/**/*.sol'

# Static analysis with slither
static-analysis:
    slither .
    @echo "Removing slither compilation artifacts..."
    forge clean

# Format contracts
fmt *args:
    forge fmt {{ args }}

# Check contract formatting
fmt-check:
    forge fmt --check

# Prerequisites check (mirrors CI)
check:
    @echo "==> Checking formatting..."
    @just fmt-check
    @echo "==> Linting..."
    @just lint
    @echo "==> Static analysis with slither..."
    @just static-analysis
    @echo "==> Cleaning..."
    @just clean
    @echo "==> Building..."
    @just build
    @echo "==> Testing..."
    @just test

# Simulate deployment (dry-run)
simulate proof-of-humanity chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployArborVote.s.sol:DeployArborVote \
        --sig "run(address)" {{ proof-of-humanity }} \
        --rpc-url {{ chain }} {{ args }}

# Deploy ArborVote
deploy deployer proof-of-humanity chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployArborVote.s.sol:DeployArborVote \
        --sig "run(address)" {{ proof-of-humanity }} \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} {{ args }}

# Publish contracts to the Soldeer registry
publish version *args:
    forge soldeer push arborvote-contracts~{{ version }} {{ args }}
