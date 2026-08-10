---
status: accepted
date: 2026-08-11
---

# The tally is centered at the market's undecided price, and a refuted argument sways nothing

ADR-0011 blended two scales and recorded the tension as an open question: an argument's own approval
lived on 0..1, where zero means fully rejected, while the descendants' aggregate it was blended with
lived on -1..1, where zero means neutral. Two failures followed, both observed live:

- **The market could weaken an attack but never neutralize it.** The fold took an argument's raw
  approval as its strength, so an attack the market rated worthless — 50%, the price a market can
  actually reach — still dragged its parent by half a full approval. Debate 3 finished with 45 of 48
  markets at their seeded prices: every surviving attack landed at ≥50% strength, and the only
  working answer to an attack was a counter-attack (`incentives.md` §9).

- **A demolished argument switched sides.** Once a sub-debate's negative aggregate outweighed the
  argument's own unsigned approval, the blend crossed zero, and the stance negation turned the
  refuted argument into support for the thing it attacked. Debate 4, argument 7: an attack rated 60%
  carrying two ~90% counter-arguments blended to −55.5% and *confirmed the thesis it was written
  against* at +5.6%. That hands out a strategy — plant a weak attack and refute it (the straw-man
  pump), which paid better than arguing for the thesis directly.

## Decision

One signed scale, zero at the market's undecided price, and a one-sided clamp where rating becomes
sway:

```
approval(A)  = MAX · (con − pro) / (pro + con)                       — centered, 50% ⇒ 0
rating(A)    = ( votes(A) · approval(A) + subtree(A) · aggregate(A) )
               / ( votes(A) + subtree(A) )                           — signed, < 0 ⇒ refuted
sway(A)      = ± max( rating(A), 0 )                                 — sign from stance
```

A child folds `sway(A)` into its parent's descendants' aggregate at its whole subtree's stake,
exactly as before; the aggregate and the own approval now live on the same scale, so the blend is a
mean of like quantities.

- **A refuted argument is silenced, never inverted.** This resolves ADR-0011's recorded open
  question — sub-neutral conviction does not argue against its own side, it stops arguing. The
  market gains the power to nullify an argument (rate it to neutral) without gaining the power to
  conscript it.

- **A silenced argument keeps its weight.** It folds at zero strength but full subtree stake,
  dampening its neighborhood. The alternative — dropping refuted subtrees from the mean — would hand
  their share to the surviving siblings, so refuting one attack would *strengthen* the others and
  defense would backfire. Keeping the weight also preserves the invariant that the thesis'
  accumulated weight ends at the debate's `totalVotes`.

- **Silence never confirms.** The outcome stays strictly `> 0`, and zero is now the resting state of
  an empty, all-refuted, or balanced tree — all of which read objected. A thesis is confirmed only
  by positive net endorsement.

- **The seed floor is the neutral point.** An argument seeded at 50% carries no sway until the
  market moves it; the range's midpoint, 75%, seeds at exactly half sway with symmetric room to be
  doubled or erased. Deliberately neutral seeds (rate this, I don't endorse it) stay legal.

## Consequences

- `ArgumentImpactCalculated` becomes `ArgumentRated` and carries the signed rating; "impact", which
  conflated the rating with the sway, leaves the vocabulary (`CONTEXT.md`).

- The tally's sensitivity to price doubles: sway moves 2 points per approval point, so the
  last-block snipe (§5 of `incentives.md`) buys twice the movement upward — while downward snipes
  now bottom out at silence instead of paying all the way to zero. The time-weighted tally remains
  the designated systemic fix, deliberately not bundled here.

- Pushing an overrated argument below neutral is now finishing work the tally honors with silence,
  not a trade that overshoots into the opposite side — the corrective job §10 of `incentives.md`
  wants priced stays a bounded one.

- The weight-stuffing decoy vector is unchanged: a crashed decoy already contributed ~nothing; under
  the clamp it contributes exactly nothing, and its weight still dilutes. Tracked where it was.

- The frontend's centered display convention (`formatApproval`, +20% for a 60% market) becomes the
  exact tally semantics instead of a reading aid that disagreed with the fold.

- Deployed contracts are immutable (ADR-0006): this ships as a new deployment, and debates on
  earlier deployments tally under the rules they were created with.