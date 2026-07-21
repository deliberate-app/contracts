---
status: accepted
date: 2026-07-21
---

# The market fee is a per-debate creator parameter, not a protocol constant

The market fee — the percentage of every stake accrued to the staked argument's creator — was the
protocol constant `Parameters._FEE_PERCENTAGE = 5`. ADR-0007 already flagged 5% as possibly too
high, and a forensic replay of a production debate (`test/Deliberate.market.t.sol`) made the
failure concrete: in a thin, quickly-corrected market the flat 5% exceeded the entire remaining
upside, so the first accurate rater *lost* tokens for being right (98 back from 100 staked). The
same trade at 1% earns tokens. No single constant serves both a two-person testnet debate and a
deep, contested market.

## Decision

`createDebate` takes a `feePercentage` (0–99), stored per debate in `Debate.Data`, emitted in
`DebateCreated`, returned by the `debates()` getter, and read by `quoteStake` for every stake on
any of the debate's arguments. The fee is fixed for the debate's lifetime — participants never see
it change under an open position.

- **Creator-chosen, like the schedule and the bounty.** The debate creator already prices the
  debate's time windows and prize; the author-compensation level is the same kind of per-debate
  economic knob. Market forces discipline the choice: a greedy fee deters raters, a zero fee
  removes the author revenue that pays for argument quality (incentives.md §2).
- **Hard cap 99.** A fee of 100% or more would let a stake degenerate into a pure fee transfer
  moving no market (`net = 0`); below 100, every nonzero stake keeps `net ≥ 1`. Anything softer
  (recommended ranges, warnings) is frontend guidance, not protocol law.
- **Zero is allowed.** A feeless debate is coherent — authors then play purely for bounty and
  influence — and banning it would encode one economic opinion into the protocol.
- **The frontend defaults to 1%**, the level at which the replayed lone-corrector trade breaks
  even and turns profitable; the default lives in the UI, not the contract.

## Consequences

Fee-dependent conclusions in [incentives.md](../incentives.md) (the ~5% correction threshold, the
`20 × deposit` author break-even) become per-debate: threshold ≈ fee, break-even ≈
`(100 / fee) × deposit` stake volume. The "tune the fee level with usage data" open question closes
— tuning moved to debate creators; what remains observable is which fees debates actually choose.
