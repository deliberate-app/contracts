---
status: accepted
date: 2026-08-14
---

# The tally reads time-weighted approvals and time-weighted stakes

Both inputs the tally consumes are snapshots of the rating window's last block, and §5 of
`incentives.md` catalogues what that costs:

- **The last-block snipe.** The tally reads the final approval, so pushing a thin market in the
  closing seconds buys a full window's worth of rating for the fee plus rounding — nobody is left
  to correct it. The time-weighted tally has been the designated systemic fix since ADR-0012
  doubled the snipe's upward leverage.

- **Weight stuffing.** Stake is voice (ADR-0011) the moment it lands, and volume at the price
  extremes round-trips nearly free at settlement — so subtree weight is purchasable at fee cost,
  and correcting a stuffed argument's price feeds its weight instead of removing it. Marked open
  in §5.

## Decision

One accumulator per input, both over the rating window `W`, updated before each stake moves the
market:

```
twapApproval(A) = Σ approval(A)·Δt / W        — the price, weighted by how long it stood
twapVotes(A)    = Σ votes(A)·Δt / W           — the stake, weighted by how long it was held
```

The tally consumes these wherever it read `approval(A)` and `votes(A)` before: the centered own
approval becomes `2·twapApproval − 1`, and every weight in the blend and the fold — the votes, the
subtree stakes, the aggregate's weighted mean — is built from `twapVotes`. Redemption is untouched
by this decision (ADR-0014 changes it separately).

- **A price is bought by holding it, not by having the last word.** A push in the closing seconds
  moves the average by the tail fraction of the window; moving it materially means holding a
  mispriced market against every corrector all window — the attack subsidizes the honest side.

- **Weight is bought the same way.** Deposits land during editing and stand the whole window, so an
  argument's seeded weight counts in full; rating-phase stakes earn weight in proportion to the
  time they are held and exposed. Stuffed weight — stake placed to be voice, not to be right — pays
  a full window of crashable exposure for what it used to get free. "Stake is voice" (ADR-0011)
  becomes *stake held is voice*.

- **Early action is worth strictly more than late action, by construction.** An early correction
  collects the better fill, the larger share of the average, and the fuller weight. This is the
  incentive the protocol wants priced, made literal in the formula.

## Consequences

- Late information is doubly muted: a true discovery in the window's closing minutes moves both the
  price average and its weight by only the tail fraction. The rating window's length is the knob
  that prices this trade-off, chosen per debate by the creator.

- Two accumulators and a last-update timestamp per argument, O(1) on each stake and at the tally;
  the tally's inputs change, its structure does not.

- §5's snipe row moves from "designated fix" to fixed by design, and the weight-stuffing vector
  closes to its residual: stuffing now costs a full window of locked, correctable exposure.

- Deployed contracts are immutable (ADR-0006): this ships as a new deployment, together with
  ADR-0014, and debates on earlier deployments tally under the rules they were created with.
