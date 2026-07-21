---
status: accepted
date: 2026-07-10
---

# Arguments are rated via AMM share markets, not quadratic voting

The 2020–2021 design (old monorepo, docs site, whitepaper) rated arguments by quadratic voting: casting weight `W` cost `W²` vote tokens. The contract now implements per-argument AMM share markets instead — participants invest vote tokens in an argument's pro or con shares (`investInPro`/`investInCon`, mint + swap with a 5% fee) and redeem them after the tally — and this is the canonical mechanism. Markets produce a continuous impact signal, let later participants price in earlier information, and reward accurate early conviction through share appreciation; quadratic voting only measures preference intensity and gives no one a reason to rate other people's arguments carefully.

## Considered Options

- **Quadratic voting** — the original design; rejected in favour of markets, so don't resurrect it when reading the outdated docs/whitepaper.

## Consequences

- The swap formula is not final (`Deliberate.sol:939`, `TODO Revisit formulas`) — finishing that math is finishing this decision, not changing it.
- `docs/rating.md` (quadratic-cost formulas) and the whitepaper's mechanism description are outdated and need rewriting; `docs/ratingmarkets.md` — the stub — is the page that should carry the real mechanism.
