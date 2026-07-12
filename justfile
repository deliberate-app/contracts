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

# Deploy ArborVote together with a MockProofOfHumanity (test networks without a real registry)
deploy-with-mock deployer chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployArborVote.s.sol:DeployArborVote \
        --sig "runWithMockPoH()" \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} {{ args }}

# --- Verification ---
# The deploy recipes verify inline when passed `--verify ...`; these re-verify a
# standing deployment (constructor args and all) when that inline pass was skipped
# or timed out. ArborVote's constructor takes the Proof of Humanity address, so it
# must be supplied to reconstruct the constructor arguments.

# Verify a Base Sepolia deployment (ArborVote + its bundled MockProofOfHumanity) on Blockscout (keyless)
verify-base-sepolia arborvote proof-of-humanity *args:
    forge verify-contract {{ arborvote }} src/ArborVote.sol:ArborVote \
        --constructor-args $(cast abi-encode "constructor(address)" {{ proof-of-humanity }}) \
        --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/ --watch {{ args }}
    forge verify-contract {{ proof-of-humanity }} test/mocks/MockProofOfHumanity.m.sol:MockProofOfHumanity \
        --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/ --watch {{ args }}

# Verify ArborVote on any Blockscout explorer (keyless); pass the explorer's /api/ URL
verify-blockscout address proof-of-humanity verifier-url *args:
    forge verify-contract {{ address }} src/ArborVote.sol:ArborVote \
        --constructor-args $(cast abi-encode "constructor(address)" {{ proof-of-humanity }}) \
        --verifier blockscout --verifier-url {{ verifier-url }} --watch {{ args }}

# Verify ArborVote on Sourcify (keyless, chain-agnostic)
verify-sourcify address proof-of-humanity chain *args:
    env -u ETHERSCAN_API_KEY forge verify-contract {{ address }} src/ArborVote.sol:ArborVote \
        --constructor-args $(cast abi-encode "constructor(address)" {{ proof-of-humanity }}) \
        --chain {{ chain }} --verifier sourcify --watch {{ args }}

# Verify ArborVote on an Etherscan-family explorer (needs ETHERSCAN_API_KEY)
verify-etherscan address proof-of-humanity chain *args:
    forge verify-contract {{ address }} src/ArborVote.sol:ArborVote \
        --constructor-args $(cast abi-encode "constructor(address)" {{ proof-of-humanity }}) \
        --chain {{ chain }} --verifier etherscan --watch {{ args }}

# Publish contracts to the Soldeer registry
publish version *args:
    forge soldeer push arborvote-contracts~{{ version }} {{ args }}
