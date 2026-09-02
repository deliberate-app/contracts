---
status: accepted
date: 2026-07-14
---

# The outcome is a credible deliberation signal, not a manipulation-proof oracle

Debate outcomes are meant to be consumable by automation (e.g. a DAO spending funds on a confirmed
thesis), which raises the question of how manipulation-proof the outcome boolean must be. We decide:
**deliberation-grade, not oracle-grade**. An egalitarian game in which every verified human gets the
same 100 non-purchasable points can never out-secure an attacker whose external budget exceeds the
participants' internal stakes — oracle-grade integrity would require capital-at-risk escalation
(challenge bonds, escalating juries à la Kleros/UMA, open-capital futarchy), a different protocol.
Deliberate instead optimizes what it can be best at: making an argument tree expensive to distort
*quietly* (every manipulation is profit for whoever corrects it) and surfacing how contested the
answer was.

## Consequences

- Integrity guardrails live **consumer-side** and are documented in
  [incentives.md §6](../incentives.md): reference the debate by its id, which is unique and never
  changes, and quote its thesis in the proposal (the text is in the `DebateCreated` log and nowhere
  in state, ADR-0015); require quorum and margin, timelock past the claim window, keep a
  veto/challenge path. No in-protocol quorum parameters.
- The one designated in-protocol hardening is the **time-weighted tally** (incentives.md §5): the
  tally reads time-weighted approvals so a last-block snipe cannot flip the outcome for the cost of
  a fee, while redemption keeps paying final reserves and stays solvent.
- The bounty layer may assume this posture: it rewards net winners of the internal game and does not
  pretend to price external bribery out of existence.
