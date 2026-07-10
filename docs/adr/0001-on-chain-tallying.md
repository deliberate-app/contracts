---
status: accepted
date: 2026-07-10
---

# Tallying happens on-chain

The whitepaper leaves open where the tallying phase runs, and a Rust off-chain tally prototype (`offchain_tally`, 2022) was started but never got past a stub; it has been deleted. We tally entirely on-chain: `tallyTree` / `_tallyNode` recursively aggregate impact from the leaf arguments up to the root, because a tally that anyone can trigger and verify without extra infrastructure is the whole point of putting the debate on-chain, and no off-chain component has to be built, hosted, or trusted.

## Consequences

- Tree size and depth are gas-bounded; very large debates may exceed block limits.
- The storage layout (per-argument market balances, leaf-ID arrays, `untalliedChilds` counters) is designed around synchronous on-chain aggregation. Revisiting off-chain tallying later (e.g. for L2 scale) is a major refactor of the entire contract, not a swap-out.
