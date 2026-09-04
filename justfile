# Show commands before running (helps debug failures)
set shell := ["bash", "-euo", "pipefail", "-c"]

# The Blockscout instance the verify recipes use. Blockscout is what gnosisscan.io serves; another
# chain needs the API URL of its own instance.
blockscout_url := "https://gnosis.blockscout.com/api/"

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
# --ir-minimum is required: coverage instrumentation disables the optimizer and via_ir, and the
# tally hits "stack too deep" without it. That same unoptimized build puts the tally's gas
# benchmarks far over their bounds, which only mean anything against the shipped build - so the
# benchmark file sits out the coverage run rather than reporting failures it cannot avoid.
coverage *args:
    forge coverage --ir-minimum --no-match-coverage "(test|script)" --no-match-path "test/*.gas.t.sol" {{ args }}

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
simulate chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployDeliberate.s.sol:DeployDeliberate \
        --sig "run()" \
        --rpc-url {{ chain }} {{ args }}

# Deploy Deliberate. Who may join is chosen per debate, so the contract takes no constructor arguments.
deploy deployer chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployDeliberate.s.sol:DeployDeliberate \
        --sig "run()" \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} {{ args }}

# Simulate the identity registry factory deployment (dry-run)
simulate-registry-factory chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployIdentityRegistryFactory.s.sol:DeployIdentityRegistryFactory \
        --sig "run()" \
        --rpc-url {{ chain }} {{ args }}

# Deploy the identity registry factory; it also clones the registry admitting every registered Circles human
deploy-registry-factory deployer chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployIdentityRegistryFactory.s.sol:DeployIdentityRegistryFactory \
        --sig "run()" \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} {{ args }}

# --- Verification ---
# The deploy recipes verify inline when passed `--verify ...`; these re-verify a
# standing deployment when that inline pass was skipped or timed out. Deliberate
# takes no constructor arguments, so nothing has to be reconstructed.

# Verify Deliberate on Sourcify, Etherscan and Blockscout
verify address chain: (verify-sourcify address chain) (verify-etherscan address chain) (verify-blockscout address chain)

# Verify Deliberate on Sourcify (keyless, chain-agnostic)
verify-sourcify address chain *args:
    env -u ETHERSCAN_API_KEY forge verify-contract {{ address }} src/Deliberate.sol:Deliberate \
        --chain {{ chain }} --verifier sourcify --watch {{ args }}

# Verify Deliberate on an Etherscan-family explorer (needs ETHERSCAN_API_KEY)
verify-etherscan address chain *args:
    forge verify-contract {{ address }} src/Deliberate.sol:Deliberate \
        --chain {{ chain }} --verifier etherscan --watch {{ args }}

# Verify Deliberate on Blockscout (keyless; pass another instance's API URL as the third argument)
verify-blockscout address chain url=blockscout_url:
    env -u ETHERSCAN_API_KEY forge verify-contract {{ address }} src/Deliberate.sol:Deliberate \
        --chain {{ chain }} --verifier blockscout --verifier-url {{ url }} --watch

# Verify Deliberate on a custom explorer (pass its verifier URL; add `--verifier blockscout` for Blockscout)
verify-custom address chain verifier-url *args:
    forge verify-contract {{ address }} src/Deliberate.sol:Deliberate \
        --chain {{ chain }} --verifier-url {{ verifier-url }} --watch {{ args }}

# Verify the factory (constructor: the Gnosis Circles Hub); `--verifier sourcify`, or `--verifier blockscout --verifier-url $(just blockscout-url)`, picks the explorer
verify-registry-factory address chain *args:
    forge verify-contract {{ address }} src/IdentityRegistryFactory.sol:IdentityRegistryFactory \
        --constructor-args $(cast abi-encode "constructor(address)" 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8) \
        --chain {{ chain }} --watch {{ args }}

# Verify the two implementations behind the clones (a registry itself is a standard EIP-1167 proxy)
verify-registry-implementations allowlist circles chain *args:
    forge verify-contract {{ allowlist }} \
        src/adapters/AllowlistIdentityRegistry.sol:AllowlistIdentityRegistry \
        --chain {{ chain }} --watch {{ args }}
    forge verify-contract {{ circles }} src/adapters/CirclesIdentityRegistry.sol:CirclesIdentityRegistry \
        --constructor-args $(cast abi-encode "constructor(address)" 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8) \
        --chain {{ chain }} --watch {{ args }}

# Print the Blockscout API URL, for passing to the registry verify recipes
blockscout-url:
    @echo {{ blockscout_url }}

# Publish contracts to the Soldeer registry
publish version *args:
    forge soldeer push deliberate-contracts~{{ version }} {{ args }}
