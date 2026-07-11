---
status: accepted
date: 2026-07-11
---

# Argument markets are constant-product AMMs; approval is the pro-share price

The placeholder swap formulas (`TODO Revisit formulas`) mixed two incompatible models: reserves were
read directly as approval (`pro/(pro+con)`) while the swap mechanics drained the pool like an
inverse-reserve AMM. We finalize the market as a constant-product AMM with scarcity pricing:
investing pro takes pro shares out of the reserve, making them scarcer and more expensive —
**approval is the price of belief, read as `con/(pro+con)`**. Investing con is the mirror image.
Whoever spots an under- or overrated argument early and invests profits at redemption once the
rating corrects: after the tally, each pro share pays the final approval, each con share the
complement, out of the market's collateral.

Mechanics for an investment of `n` net vote tokens (after the fee) into pro:
`con' = con + n`, `pro' = ceil(pro·con / con')`, and the investor receives `pro + n − pro'` shares.
The ceiling rounding keeps both reserves at ≥ 1 forever, so a market can never be drained or
divide by zero. Solvency is structural: every net token conceptually mints one pro and one con
share (investor side + pool side), so total redemption liability is exactly `votes·A* + votes·(1−A*)
= votes`, and the pool's own unredeemed shares leave slack.

## Consequences

- The original deposit seeding `split(100 − initialApproval, initialApproval)` was correct under
  these semantics and is restored; the true orientation bugs were `_calculateImpact` and the
  frontend reading `pro/(pro+con)`, both now flipped to `con/(pro+con)`. (This supersedes the
  seeding half of the earlier "orient the initial approval toward the pro share" fix.)
- `initialApproval` is bounded 50..99: a 100 seed would empty the pro reserve and freeze the market.
- `proIssued`/`conIssued` and both placeholder swap functions are removed; redemption is the
  final-price payout above.
- The thesis (argument 0) has no market and is explicitly untradeable.
- Market depth equals the 10-token deposit, so prices move sharply on small trades — acceptable
  for now; deeper seeding (e.g. bounty-funded liquidity) is a future knob.
- The 5% investment fee (creator-claimable, ADR-independent) may be too high for profitable
  correction trading; revisiting the level is tracked in the project TODO.
