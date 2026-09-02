# Deliberate Contracts

A voting module for deliberative decision-making using argument trees.

Deliberate lets participants build a tree of pro/con arguments below a debate thesis, stake vote tokens on
argument markets to rate them, and finally tally the tree to determine the outcome. The `Deliberate` contract
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

Who may join is chosen per debate, so `Deliberate` takes no constructor arguments. A debate names an
`IIdentityRegistry` at creation: the zero address admits everyone; an `AllowlistIdentityRegistry` is a group its
owner curates and any number of debates can share; `CirclesIdentityRegistry` reads the Circles v2 Hub on
Gnosis Chain, admitting any Circles human (or whoever a chosen avatar trusts); `EASIdentityRegistry` gates on an
attestation. The deploy script puts the any-Circles-human registry beside `Deliberate`, so every deployment
offers all three modes. With a funded [keystore account](https://getfoundry.sh/cast/reference/cast-wallet-import)
(`cast wallet import`) and the `gnosis` endpoint from `foundry.toml` (or any RPC URL in its place):

```sh
just simulate gnosis                    # dry run
just deploy <KEYSTORE_ACCOUNT> gnosis   # broadcast
just verify <DELIBERATE_ADDRESS> gnosis # Sourcify and Etherscan; `verify-sourcify`, `verify-etherscan`, `verify-custom` singly
just verify-circles-registry <REGISTRY_ADDRESS> gnosis
```

The script prints both addresses. The `deliberate` address and its deployment block feed the indexer's
`config.yaml` and the frontend's `VITE_DELIBERATE_ADDRESS`; the registry address feeds the frontend's
`VITE_CIRCLES_REGISTRY` (deployment pipeline: contracts -> indexer -> frontend).

The live deployment, recorded in `broadcast/DeployDeliberate.s.sol/100/run-latest.json` and verified on
Sourcify and Gnosisscan:

| Gnosis Chain (100) | address | block |
|---|---|---|
| `Deliberate` | [`0x28b939ed3F67c8eaB198e46E9d41CcB4d19c6DE3`](https://gnosisscan.io/address/0x28b939ed3F67c8eaB198e46E9d41CcB4d19c6DE3) | 48049642 |
| `CirclesIdentityRegistry` (any Circles human) | [`0x74bEF28610f70831429dc8d9014Bdeb5C60C4c31`](https://gnosisscan.io/address/0x74bEF28610f70831429dc8d9014Bdeb5C60C4c31) | 48049642 |

## Layout

```
src/        The Deliberate contracts, interfaces, types, and utilities.
test/       Foundry tests and mocks.
script/     Deployment scripts.
```
