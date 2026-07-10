---
status: accepted
date: 2026-07-10
---

# No on-chain disputes — the rating market is the moderation mechanism

ADR-0003 delegated dispute rulings to an external arbitrator; we now remove disputing entirely: no `IArbitrator`/`IArbitrable` integration, no dispute states, no dispute storage. The rating market already is the quality signal — badly rated arguments lose influence by construction and frontends can hide them; an argument that clears the deposit and Proof-of-Humanity gates is allowed to stand and be rated down rather than adjudicated away.

## Considered Options

- **External arbitrator (ADR-0003)** — rejected: inherits a third-party protocol's trust assumptions, fees, and ruling latency; an unruled dispute would block the tally on a clock we don't control; and it drags a full `IArbitrable` surface (evidence submission, rulings, ERC-20 fee handling, reentrancy protection) into a module whose mechanism doesn't need it.
- **In-house curator/juror court** — already rejected in ADR-0003.

## Consequences

- Supersedes ADR-0003.
- Removed from the contract: `raiseDispute`/`resolveDispute` and their internals, `IArbitrator` + `IArbitrable`, the `arbitrator` storage field, dispute mappings/views/events/errors, and `Argument.State.Disputed`/`Invalid` (the state machine reduces to Uninitialized → Created → Final). With them go the module's only ERC-20 transfers and its only reentrancy surface (`SafeERC20`, `ReentrancyGuardTransient`).
- Anti-spam rests on the argument deposit (10 vote tokens caps a participant at ten arguments) and Proof-of-Humanity-gated joining; hiding offensive content is a frontend concern with no on-chain effect.
- A spam argument still carries its deposit's tally weight; the counter is rating it down, not removing it.
- The tally can never be blocked by an external protocol's timing.
