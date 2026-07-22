---
status: accepted
date: 2026-07-21
---

# The tally blends own approval and descendants by stake, not by a fixed 50:50

The tally blended every argument's rating as `½ · own approval + ½ · descendants' aggregate`
(`_MIX_VAL`), and a child's share among its siblings was its own market's votes. Two failures
followed:

- **A lone argument could sway its parent by at most 50%.** The empty descendants slot claimed
  half the voice unconditionally — a debate's only argument, rated to 99% approval, confirmed its
  thesis with a sway of ~50%, half of what the market said.
- **Structure beat stake.** One minimum-deposit child owned half of any parent's blend outright: a
  10-token con child seeded high gutted a 100+-token parent market — a burial attack priced at the
  deposit floor, uncorrectable except by out-staking the child's own tiny market.

## Decision

Both weightings follow the stake:

```
blend(A) = ( votes(A) · approval(A) + subtree(A) · descendants(A) ) / ( votes(A) + subtree(A) )
```

where `votes(A)` is A's own market stake and `subtree(A)` the total stake of A's descendants'
markets. A child folds into its parent's descendants term as a running mean weighted by its **whole
subtree's** stake (`votes + subtree`).

- **A childless argument sways with its full approval** — the 50% ceiling disappears; the thesis
  (no market of its own) remains the natural special case: pure descendants aggregate.
- **Correction is proportional to the debate that happened.** The 10-token burial child now moves a
  115-token subtree's blend by its ~9% share, and counter-staking it works at market prices.
- **A sub-debate speaks with its stake at every level.** Sibling shares weigh subtrees, not own
  markets, so the two weightings tell one story; "one token, one voice" holds up the whole tree.
- **No per-stake bookkeeping.** Subtree stakes are derived bottom-up during the (already recursive)
  tally itself — `childsVote`'s incremental maintenance on stake/move/create is gone, replaced by a
  tally-time `subtreeVotes` accumulator. The thesis' accumulated weight ends at the debate's
  `totalVotes`, an asserted invariant.
- `ArgumentImpactCalculated` now carries the argument's **blended rating** (fixed point unchanged);
  its signed pull on the parent is `isSupporting ? impact : -impact` at its subtree's weight.

## Consequences

- Approval stays unsigned (0..1): a lone supporting argument confirms its thesis at any nonzero
  rating, now at full instead of half magnitude. Whether sub-neutral approval should argue
  *against* its own side is a recorded open question, deliberately not bundled here.
- Deep pockets can dominate a parent through a heavy sub-debate — by design: influence tracks
  stake, and the remedy is counter-staking the sub-debate's markets at their own prices.
- The frontend's live tally preview (`impactsOf`) mirrors the same weighting; drafts contribute
  nothing and weigh nothing until they lock in.
