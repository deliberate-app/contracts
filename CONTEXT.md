# ArborVote

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

**Argument market**:
The per-argument market in which participants buy an argument's pro or con shares with vote tokens.
_Avoid_: rating market

**Vote tokens**:
The non-transferable, debate-scoped budget every participant receives on joining, spent on argument deposits and pro/con share investments.
_Avoid_: debate tokens

**Participant**:
A Proof-of-Humanity-verified account that has joined a debate and received vote tokens.
_Avoid_: voter, debater (both are just participants acting in a phase)

**Dispute**:
A challenge to a finalized argument during the Editing phase, ruled on by the arbitrator.
_Avoid_: flag, removal request

**Arbitrator**:
The external arbitration protocol that rules on disputes; ArborVote has no court of its own.
_Avoid_: curator, juror, digital court

**Bounty**:
The stake the creator attaches to a debate, paid out to above-average participants after tallying.
_Avoid_: debate bounty, reward pool

## Phases

A debate passes through three domain phases, in order.

**Editing phase**:
The phase in which participants add, alter, move, and finalize arguments beneath the thesis.
_Avoid_: debating stage

**Rating phase**:
The phase in which participants rate arguments by investing vote tokens in their argument markets.
_Avoid_: voting phase, voting stage

**Tallying phase**:
The phase in which the tally runs and the outcome becomes final.
