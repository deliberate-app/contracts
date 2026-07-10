# Contributing

## Commit discipline

- **One commit, one change.** A commit does exactly one thing — a single fix, feature, refactor, rename sweep, or doc change — and its message says which. Never mix a mechanical rename with a behavior change; land the rename first, then the fix on top.
- **Every commit is green.** The full check gate passes on every commit, not just on the branch tip. If a commit needs a follow-up to compile or pass tests, it is not one commit.
- **Fixes carry their regression test.** A bug fix and the test that demonstrates the bug land in the same commit (test red before the fix, green after).

## Commit messages

Lowercase conventional prefix — `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:` — followed by an imperative summary. Elaborate in the body when the diff doesn't speak for itself.

## Checks

Run `just check` before every commit — it mirrors CI: format check, lint, static analysis, build, tests.
