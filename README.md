# ArborVote Contracts

A voting module for deliberative decision-making using argument trees.

ArborVote lets participants build a tree of pro/con arguments below a debate thesis, stake vote tokens on
argument markets to rate them, and finally tally the tree to determine the outcome. The `ArborVote` contract
is deployed once, has no owner, and is not upgradeable (ADR-0006); moderation happens through the rating
markets themselves (ADR-0005).

## Prerequisites

1. Get an up-to-date version of [Foundry](https://github.com/foundry-rs/foundry) with

   ```sh
   curl -L https://foundry.paradigm.xyz | sh
   foundryup
   ```

2. Optionally, to lint the contracts, install [solhint](https://github.com/protofire/solhint) using a JS package
   manager such as [Bun](https://bun.com/) with

   ```sh
   curl -fsSL https://bun.sh/install | sh
   bun install
   ```

3. Optionally, for static analysis, install [Slither](https://github.com/crytic/slither) with

   ```sh
   python3 -m pip install slither-analyzer
   ```

## Usage

#### Installation

Install the dependencies (managed with [Soldeer](https://soldeer.xyz)) with

```sh
forge soldeer install
```

#### Build

To compile the contracts, run

```sh
forge build
```

#### Tests & Coverage

To run the tests, run

```sh
forge test
```

To show the coverage report, run

```sh
forge coverage
```

#### Linting & Static Analysis

To run the linter and static analyzer, run

```sh
bunx solhint --config .solhint.json 'src/**/*.sol' && \
bunx solhint --config .solhint.other.json 'script/**/*.sol' 'test/**/*.sol' && \
slither .
```

#### Deployment

`ArborVote` takes the address of an identity registry (`IIdentityRegistry`) as its only constructor
argument — a personhood registry such as [Proof of Humanity](https://etherscan.io/address/0x1dAD862095d40d43c2109370121cf087632874dB),
or an adapter like `EASIdentityRegistry` (attestation-based, e.g. Coinbase Verifications on Base).
Against a real registry:

```sh
forge script script/DeployArborVote.s.sol:DeployArborVote \
  --sig "run(address)" <IDENTITY_REGISTRY> \
  --rpc-url <network>
```

On test networks without a registry, `runWithMockRegistry()` deploys a `MockIdentityRegistry`
(everyone counts as registered) alongside. For Base Sepolia, verified on Blockscout (keyless),
with a funded [keystore account](https://getfoundry.sh/cast/reference/cast-wallet-import) (`cast wallet import`):

```sh
forge script script/DeployArborVote.s.sol:DeployArborVote \
  --sig "runWithMockRegistry()" \
  --rpc-url https://sepolia.base.org \
  --account <KEYSTORE_ACCOUNT> \
  --broadcast \
  --verify --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/
```

The script prints both addresses; the `arborVote` address and its deployment block feed the
indexer's `config.base-sepolia.yaml` and the frontend's `VITE_ARBORVOTE_ADDRESS`
(deployment pipeline: contracts -> indexer -> frontend).

## Layout

```
src/        The ArborVote contracts, interfaces, types, and utilities.
test/       Foundry tests and mocks.
script/     Deployment scripts.
```
