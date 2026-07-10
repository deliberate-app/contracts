---
status: accepted
date: 2026-07-10
---

# Engineering standard: production-grade tooling over expedient scripts

ArborVote aims to be a professional project. We choose industry best practices and adequate, purpose-built tooling over making things work quickly: the architecture should be reliable, simple, robust, and flexible — not a bundle of stitched-together scripts. Concretely: dependencies are pinned and reproducible (e.g. dockerized services over host installs), orchestration lives in one coherent, typed place rather than being spread across shell glue, invariants are enforced by tools (fmt, lint, static analysis, tests, CI) rather than by convention, and quick fixes that violate this are recorded as debt in `TODO.md` with a path to the proper solution.

## Consequences

- The local dev stack (`frontend/scripts/dev-anvil.sh`: bash + perl extraction + cast warps orchestrating two forge scripts) is acknowledged debt under this standard — tracked in `TODO.md` for consolidation into a single typed seeding tool.
- New tooling choices should default to the ecosystem-standard instrument for the job (Foundry scripts for chain state, viem for client logic, docker compose for services) and be wired into `justfile` recipes and CI.
