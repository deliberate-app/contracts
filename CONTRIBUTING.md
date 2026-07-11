# Contributing

## Commit discipline

- **One commit, one change.** A commit does exactly one thing — a single fix, feature, refactor, rename sweep, or doc change — and its message says which.
- **Fix before renaming.** Keep mechanical renames separate from behavior changes, and land semantic fixes first, in the old vocabulary: a faithful rename of buggy code re-expresses the bug in the new vocabulary, where it reads as intended behavior. Only when fix and rename are so entangled that no ordering leaves every intermediate commit coherent may they land together, in one commit whose message says so.
- **Every commit is green and coherent.** The full check gate passes on every commit, not just on the branch tip — and no commit leaves code that makes a known defect read as deliberate.
- **Fixes carry their regression test.** A bug fix and the test that demonstrates the bug land in the same commit (test red before the fix, green after).

## Code comments

- **No ADR references in code comments.** Comments state the constraint or intent in their own words; the decision history lives in `docs/adr/` and the commit messages. A comment that only makes sense after reading an ADR is not carrying its weight.

## Commit messages

Lowercase conventional prefix — `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:` — followed by an imperative summary. Elaborate in the body when the diff doesn't speak for itself.

## Checks

Run `just check` before every commit — it mirrors CI: format check, lint, static analysis, build, tests.
