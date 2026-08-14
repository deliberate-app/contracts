---
status: accepted
date: 2026-08-14
---

# Shares settle at the tallied rating

A share redeems at its market's own closing price, so each market is its own resolution criterion.
`incentives.md` names the two costs (§7 gap 2, §9.6):

- **Nothing anchors the price but the price.** A rating market settled by itself is a beauty
  contest: the profitable trade is predicting the closing price, which is only accidentally the
  argument's quality, and a manipulator is never proven wrong against anything.

- **The tally is financially inert.** No payoff touches rating or sway, so the machinery of
  ADR-0011/0012 — subtree correction, refutation, silencing — prices nothing. In the first live run
  45 of 48 markets closed at their seeded prices and the outcome was a poll of authors; a rater who
  correctly foresaw that an argument would be demolished *by its children* earned nothing unless
  that argument's own market happened to reprice.

## Decision

A share settles against the argument's tallied rating — the tree's verdict, unclamped:

```
pro share pays  (1 + rating(A)) / 2
con share pays  (1 − rating(A)) / 2
```

with `rating(A)` exactly as the tally computes it (ADR-0012, inputs per ADR-0013), stored per
argument at the tally and read at redemption.

- **A strict generalization of the old rule.** A childless argument's rating is its own centered
  approval, so its settlement reduces to the market price — the change is exactly zero wherever the
  tree had nothing to say, and grows with the stake behind the sub-debate.

- **Arguing and staking become the same trade.** Refuting an argument through children settles its
  con shares; a lazy market no longer shields a demolished argument's shareholders behind an
  untraded price.

- **Manipulating a settlement means beating the subtree.** An argument's own price enters its
  rating only at weight `votes/(votes + subtree)`; the rest is its children's verdict, each of them
  a market where resistance is paid. Composed with ADR-0013, a snipe or a pump fights the whole
  tree over the whole window instead of one thin market in one block.

- **The clamp stays in the fold, and only there.** Settlement uses the signed rating over its full
  range, so refutation depth keeps paying con-holders below neutral; sway keeps silencing refuted
  arguments toward the parent (ADR-0012). No dead zone reaches a trader.

## Consequences

- Solvency needs no normalization: each side's reserves plus outstanding shares equal that side's
  seed plus every net stake (`_stake` adds each net stake to both side totals; `_createArgument`
  splits the whole deposit into the reserves), so any settlement value in [0, 1] pays out at most
  the tokens the market took in — the difference joins the leakage §1 of `incentives.md` already
  accepts. A fuzz test pins the bound: per market, `Σ payouts ≤ deposit + Σ net stakes` for
  arbitrary ratings.

- The rating becomes storage, not just an event: `subtreeVotes` is repurposed mid-tally, so
  redemption reads a stored rating written by `_tallyNode` instead of re-deriving it.

- Weight stuffing gains a private payout channel — planting supportive children under an argument
  one holds shares in lifts its rating. Bounded by ADR-0013 (manufactured weight costs a full
  window of exposure) and by the clamp (a crashed plant folds at zero sway and its weight drags the
  parent's rating toward neutral); tracked in §5 as the residual of the closed vector.

- §7 gap 2 narrows, it does not close: the resolution criterion moves from each market to the tree,
  which is still endogenous to the debate. The outcome remains a signal, not an oracle (ADR-0008).

- Deployed contracts are immutable (ADR-0006): ships as a new deployment together with ADR-0013;
  shares on earlier deployments redeem under their original rule.
