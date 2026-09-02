# Deliberate

An on-chain voting module for deliberative decision-making: participants build a tree of pro and con arguments beneath a thesis, back arguments with vote tokens, and the tallied tree determines the outcome.

## Language

**Debate**:
A single decision process on one thesis, with its own participants, tokens, phases, and outcome.

**Creator**:
The participant who opens a debate: writes the thesis, sets its parameters, and attaches the bounty.
_Avoid_: issuer, author of the root argument

**Thesis**:
The statement being decided, forming the root of a debate's argument tree.
_Avoid_: root node, root argument, statement, proposition

**Argument**:
A node in the debate tree that supports (pro) or attacks (con) its parent; the only node type. Evidence and sources belong inside an argument's content.
_Avoid_: node, fact node

**Content**:
The text of a thesis or argument: 1 to 256 bytes of UTF-8, passed to the call that creates or alters it, published by that call's event and never stored. Readers take it from the log, or from an indexer that folded the log.
_Avoid_: contentURI, digest, CID, IPFS

**Tally**:
The on-chain, leaves-to-root aggregation of argument sway that produces the debate's outcome,
reading time-weighted inputs: every price and every stake counts for the seconds it stood in the
rating window (ADR-0013), so a rating is bought by holding a price, not by having the last word,
and weight is earned by exposure. Each argument's tallied rating blends its own approval with its
descendants' aggregate, weighted by the stake behind each (ADR-0011) — a childless argument's
rating is its approval; a debated one is corrected in proportion to the stake that debate
attracted.

**Tallied rating**:
The tally's verdict on one argument, on a signed scale whose zero is the market's undecided
price: positive is endorsed, negative is refuted — and the value the argument's shares settle
against at redemption (ADR-0014). Distinct from approval (the market's live, unsigned price) and
from sway (what the rating exerts on the parent).
_Avoid_: impact (the legacy name — it conflated the rating with the sway), score

**Sway**:
An argument's pull on its parent's rating: its tallied rating clamped at neutral — a refuted
argument sways nothing rather than aiding the other side (ADR-0012) — signed by its stance and
carrying its whole subtree's stake. A refuted child keeps its weight in the parent's aggregate,
so a demolished sub-debate dampens its neighborhood instead of vanishing from it.
_Avoid_: pull, impact

**Outcome**:
The tally's verdict on the thesis — confirmed or objected. A credible deliberation signal, not a manipulation-proof oracle: automation that consumes it must bring its own guardrails.
_Avoid_: result, decision

**Argument market**:
The per-argument market in which participants buy an argument's pro or con shares with vote tokens.
_Avoid_: rating market

**Good-argument share / Bad-argument share**:
The display names of an argument market's pro and con shares (`shares.pro`/`shares.con` in the
contract). A good-argument share pays out with the argument's tallied rating at redemption — the
tree's verdict, which reduces to the market's own time-weighted price when nothing was argued
beneath the argument — and a bad-argument share its complement; the name says what the claim is
on, not which side of the parent the argument takes. Bought by staking "underrated" and "overrated" respectively.
_Avoid_: pro share, con share (in user-facing copy — they collide with the pro/con stance of
arguments)

**Approval**:
An argument market's current rating of the argument — the price of belief in it, rising as participants stake on the pro side (the argument is underrated) and falling as they stake on the con side (overrated).
_Avoid_: score, rating value

**Vote tokens**:
The non-transferable, debate-scoped budget every participant receives on joining, spent on argument deposits and pro/con stakes.
_Avoid_: debate tokens

**Locking window**:
The time a new or edited argument stays a draft before it locks in — chosen per debate by the creator, and the floor for each phase's length. Kept short so replies beneath new arguments are never held up for long.
_Avoid_: draft window, time unit (the legacy parameter name — nothing is a multiple of it anymore)

**Market fee**:
The share of each stake that accrues to the argument's creator, claimable once the debate is finished — the authorship incentive for arguments that attract rating volume.

**Participant**:
A personhood-verified account that has joined a debate and received vote tokens.
_Avoid_: voter, debater (both are just participants acting in a phase)

**Identity registry**:
The pluggable on-chain registry the join gate queries to check that an account belongs to a verified person.
_Avoid_: Proof of Humanity (one legacy provider, not the concept)

**Bounty**:
The stake the creator attaches to a debate, claimable after tallying by participants who ended with more vote tokens than the initial grant — those who net won points by arguing or rating.
_Avoid_: debate bounty, reward pool

**Excess**:
The vote tokens a participant ends with beyond the initial grant; the score a bounty claim is proportional to.
_Avoid_: profit, surplus

**Claim window**:
The period after a debate finishes during which bounty claims are open; once it closes, the creator may sweep the remainder.
_Avoid_: payout period

**Sweep**:
The creator reclaiming a bounty's unclaimed remainder once the claim window has closed — by design most of the pool on consensual debates.
_Avoid_: refund (top-ups are donations, nothing is owed back)

## Phases

A debate passes through three domain phases, in order.

**Editing phase**:
The phase in which participants add, alter, move, and finalize arguments beneath the thesis.
_Avoid_: debating stage

**Rating phase**:
The phase in which participants rate arguments by staking vote tokens on their argument markets.
_Avoid_: voting phase, voting stage

**Tallying phase**:
The phase after rating ends in which the tally runs.

**Finished**:
The terminal state of a debate once the tally has run: the outcome is final and argument shares can be redeemed. Not a phase — a debate is finished, it is not finishing.
_Avoid_: tallied, closed, ended
