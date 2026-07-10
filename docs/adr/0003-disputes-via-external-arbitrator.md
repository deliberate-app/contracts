---
status: superseded by ADR-0005
date: 2026-07-10
---

# Disputes are ruled by an external arbitrator, not an in-house court

The 2021 design had a native curation system: curators flag inappropriate arguments and post deposits, authors concede or contest, and an in-house "digital court" of jurors rules. We delegate instead: anyone can raise a dispute on a finalized argument during the Editing phase, and an external `IArbitrator` (Aragon-protocol-style interface) rules on it — a voting module should not also be a court, and arbitration protocols bring their own jurors, appeal rounds, and incentive design that we would otherwise have to rebuild and secure ourselves.

## Considered Options

- **In-house curator/juror court** (docs-era design) — rejected: large security- and incentive-design surface orthogonal to the module's purpose.
- **Layered (cheap in-house flags, escalate to external arbitrator)** — rejected for now; can be revisited on top of the external path without reversing it.

## Consequences

- The Curator stakeholder role does not exist on-chain; `docs/curation.md` and `docs/stakeholders.md` describe a dead design.
- `User.Role.Juror` is dead code — remove it in the pending pre-deployment breaking sweep (see project `TODO.md`).
- The module inherits the chosen arbitrator's trust assumptions and fee model; deployments must be initialized with a live arbitrator address.
