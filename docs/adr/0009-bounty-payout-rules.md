---
status: accepted
date: 2026-07-15
---

# The bounty pays excess over the initial grant, in-module, within a fixed claim window

The bounty layer ([incentives.md §3–4](../incentives.md)) turns a debate into a fundable contest:
the creator posts an ERC-20 prize, net winners of the internal vote-token game claim shares of it.
Building it forced five calls, each with real alternatives:

- **In-module, not a wrapper.** Claims read `tokens`, the participant count, and the finished latch
  directly; a wrapper would re-expose all three across a trust boundary and double every flow
  (approvals, addresses, indexing) for no v1 benefit. The uncurated-ERC-20 risk stays contained by
  `SafeERC20`, checks-effects-interactions, and per-debate pools — a hostile token can only grief
  its own bounty's transfers. Extraction into a wrapper remains possible before any mainnet.
- **The prize is fixed at creation.** `createDebate` carries `(bountyToken, bountyAmount)` —
  `address(0)` means no bounty, amount 0 with a token invites donations. Participants never see the
  token switch under them; `fundBounty` tops up the fixed token until the debate finishes, and
  top-ups are donations, not refundable positions. Funding uses balance-delta accounting, so
  fee-on-transfer tokens fund what actually arrived.
- **Eligibility is `tokens > 100`, the denominator is `100·N`.** Strictly-above-the-grant kills
  idle-join claims; the fixed denominator caps what a `k`-ring of verified identities can funnel to
  `(k−1)/N` of the pool and keeps claims O(1) — no global settlement barrier. The unclaimed
  remainder is the product working as designed (it measures how uncontested the debate was), not
  dust.
- **Claims settle-and-claim in one call.** `claimBounty(debateId, argumentIds)` batch-redeems the
  given shares, claims creator fees on the caller's own arguments among them, then pays
  `pool × (tokens − 100) / (100 × N)` — one transaction, and claiming before settling (an
  irreversible under-claim, since claims are one-shot) is structurally impossible.
- **The claim window is a 7-day constant.** A creator-chosen window would need a floor anyway — an
  unfloored one lets the creator sweep before anyone can claim — and a schedule-derived one gives
  hour-scale debates hour-scale windows. `CLAIM_WINDOW = 7 days` removes both failure modes and one
  knob; a floored creator knob is a recorded TODO if real usage wants faster sweeps.

## Consequences

- After the window the creator sweeps the remainder — there is no protocol fee in v1 (recorded
  TODO: possibly fold one into the market-fee mechanism later).
- The tally stamps the finish time on-chain; claims gate on `finishTime + CLAIM_WINDOW`.
- `N` (joined participants) becomes on-chain state, incremented on join — also useful to
  consumer-side quorums (ADR-0008).
- A worthless or hostile bounty token is the creator's problem by design (uncurated); the outcome
  itself stays a signal, not an oracle, per ADR-0008.
