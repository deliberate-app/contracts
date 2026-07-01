# ArborVote Contracts

A voting module for deliberative decision-making using argument trees.

ArborVote lets participants build a tree of pro/con arguments below a debate thesis, invest vote tokens into
argument markets, dispute arguments through an external arbitrator, and finally tally the tree to determine the
outcome. The `ArborVote` contract is a conventional [UUPS](https://eips.ethereum.org/EIPS/eip-1822) upgradeable
contract owned via OpenZeppelin's `OwnableUpgradeable`.

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

The `ArborVote` implementation is deployed behind an `ERC1967Proxy` and initialized with the address of a
[Proof of Humanity](https://etherscan.io/address/0x1dAD862095d40d43c2109370121cf087632874dB) registry. To simulate
deployment on sepolia, run

```sh
forge script script/DeployArborVote.s.sol:DeployArborVote \
  --sig "run(address)" <PROOF_OF_HUMANITY> \
  --rpc-url sepolia
```

Append the

- `--broadcast` flag to deploy to the network,
- `--verify` flag for subsequent contract verification.

## Layout

```
src/        The ArborVote contracts, interfaces, types, and utilities.
test/       Foundry tests and mocks.
script/     Deployment scripts.
```
