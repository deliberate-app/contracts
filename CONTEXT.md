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

**Tally**:
The on-chain, leaves-to-root aggregation of argument impact that produces the debate's outcome.
Each argument's tallied rating blends its own approval with its descendants' aggregate, weighted by
the stake behind each, and a child pulls on its parent with its whole subtree's stake (ADR-0011) —
a childless argument sways with its full approval; a debated one is corrected in proportion to the
stake that debate attracted.

**Outcome**:
The tally's verdict on the thesis — confirmed or objected. A credible deliberation signal, not a manipulation-proof oracle: automation that consumes it must bring its own guardrails.
_Avoid_: result, decision

**Argument market**:
The per-argument market in which participants buy an argument's pro or con shares with vote tokens.
_Avoid_: rating market

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
