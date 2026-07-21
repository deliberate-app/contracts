# Incentives

Status: design, 2026-07-14. Sections 1–2 describe the economy as **built**; sections 3–4 specify the
**bounty layer, which is not yet implemented**; sections 5–8 analyze attacks, safe consumption,
what an oracle-grade outcome would take, and the sybil gate. Decisions here were made in a design
interview; the hard-to-reverse core is recorded in
[ADR-0008](adr/0008-outcome-is-a-signal-not-an-oracle.md).

## 1. The debate economy as built

Every participant who joins receives the same `INITIAL_TOKENS = 100` vote tokens — non-transferable,
debate-scoped, the debate's only currency. Tokens only ever move between participants (stakes,
redemptions, market fees), so the internal game is **zero-sum**: the sum of final balances is
`100·N` minus leakage (rounding dust, never-redeemed shares, never-claimed fees, and the reserves of
markets nobody traded). Influence cannot be bought, only earned inside the debate.

Two roles trade with each other through the argument-specific rating markets:

- **Authors** pay a deposit (≥ 10) to add an argument. The deposit seeds the market's reserves at
  the author's chosen initial approval (bounded 50–99%) and the author receives **no shares** — the
  deposit is sunk, ultimately redeemed by whoever holds shares. The author's revenue is the **market
  fee**: 5% of every stake on their argument, claimable as vote tokens once the debate is finished.
  Break-even is `20 × deposit` in stake volume.
- **Raters** stake tokens on a market's pro or con side and profit at redemption if the final rating
  moved their way beyond their own trade. Two facts shape this: the fee means only mispricings
  larger than ~5% are worth correcting, and the **self-impact limit** — you cannot profit from the
  price move you yourself cause — means profit requires either *other raters being wrong* or
  *mispriced seeded reserves*.

Together this is a deliberate **two-sided payment loop**: authors pay raters (the sunk deposit in
mispriced reserves is the pot that makes rating profitable even in a consensus debate), and raters
pay authors (the fee rewards arguments that attract rating volume). A "wrong" seeded approval is not
a defect — it is the subsidy that makes verifying the rating worthwhile. The balance knob between
the two sides is `fee % × expected volume` versus `deposit`, tracked in the project TODO as a
tune-with-data parameter. Honest caveat: in small, quiet debates authorship is net-negative — the
bounty layer (fees count toward excess) is what tops it up.

## 2. Why anyone participates (without a bounty)

- **The creator** gets the thesis adversarially tested: a tree of weighted, market-rated arguments
  and an outcome. The value is the *tested* answer, not the answer alone.
- **Authors** earn fees and sway the outcome — a well-placed argument recruits the whole tree
  beneath it.
- **Raters** earn trading profit from mispricings and move ratings toward their view.

These motives are real but thin at small scale; the bounty layer exists to pay for the work.

## 3. The bounty layer (planned)

The creator attaches a prize in an ERC-20 of their choosing; participants who *net win* vote tokens
claim a share of it.

**Funding.** At creation the creator names the token and deposits an amount (possibly zero — the
bounty is optional and bounty-less debates keep working). Anyone may **top up** the pool until the
debate finishes; top-ups are donations (they raise everyone's payout and are not refunded
pro-rata). The token is **uncurated**: a worthless or hostile bounty token simply fails to attract
participants (see §5 for the hostile-token vectors).

**Eligibility.** A participant qualifies iff their final balance strictly exceeds the initial grant:
`tokens > 100`, checked after they have redeemed their shares and claimed their fees. You must have
net won points — by rating mispricings or by authoring arguments that earned fees.

**Payout.** A qualifying participant's claim is proportional to their **excess** over the debate's
total initial supply:

```
claim = pool × (tokens − 100) / (100 × N)        N = number of joined participants
```

Claims are O(1) in everyone else's state — no waiting for anyone's redemption — and the claim call
**settles-and-claims**: it batch-redeems the share positions handed to it and claims creator fees
on the caller's own arguments first, so claiming before settling (an irreversible under-claim —
claims are one-shot) is structurally impossible (ADR-0009).

**Claim window and remainder.** Claims open at Finished and close after a constant **7-day claim
window** (`CLAIM_WINDOW`; a floored creator-chosen window is a recorded TODO — an unfloored one
would let the creator sweep before anyone can claim). Afterwards the creator sweeps the remainder.
There is **no protocol fee** in v1; a fee (possibly folded into the market-fee mechanism) is a
recorded TODO.

**Worked example.** 20 participants (`100·N = 2000`), pool 1000 DAI. Alice ends at 180 (excess 80)
→ claims 40 DAI. Bob ends at 130 → 15 DAI. Everyone else broke even or lost. Claimed: 55 DAI;
the creator sweeps 945 DAI after the window.

## 4. Why these rules

**Strictly above 100, not above average.** Zero-sum plus leakage means the mean final balance is
always ≤ 100 — so "above average" would let a verified human join, do *nothing*, sit at exactly 100
above the mean, and claim. Attaching money to that makes idle-joining the dominant strategy. The
average is also not computable on-chain until every participant has redeemed and claimed, which no
one can force. `tokens > 100` kills both problems and is a constant-time check.

**Fixed denominator `100·N`, not `Σ excess`.** Pro-rata over total excess would always pay out the
whole pool — but total excess is unknowable until global settlement (two-phase machinery), and a
wash-trading coalition would capture its share of the *whole* pot however small the honest activity.
Against the fixed denominator, a coalition of `k` participants funneling their own points to their
winners manufactures at most `100·(k−1)` excess — **at most `(k−1)/N` of the pool**, paid for in
real verified identities.

**The remainder is the point, not a bug.** The claimed fraction `c = Σ excess / (100·N)` measures
exactly how much capital changed hands — how contested the debate was and how wrong the losing side
was. Expected magnitudes:

| Debate character | Claimed `c` | Remainder |
|---|---|---|
| Consensus (seeds near truth, raters agree) | ~1–5% | ~95–99% |
| Genuinely contested (≈60% deployed, a third wrong) | ~15–25% | ~75–85% |
| Polarized blowout | ~30–50% | ~50–70% |
| Adversarial ceiling (one account sweeps all) | → ~100% | → 0 |

The creator therefore posts a **maximum** prize and pays in proportion to the disagreement actually
resolved — posting a generous bounty on a question you believe settled is cheap, and it becomes
expensive precisely when real information surfaces. Drivers of `c`: wrong-way capital (dominant),
fee volume to authors, deposit capture by raters; reduced by leakage; inflated by collusion up to
the headcount bound above.

## 5. Attacks on the bounty and the outcome

The outcome (`descendantsImpact > 0` at the root; a tie reads as objected — fail-safe) is a
**credible deliberation signal, not a manipulation-proof oracle** (ADR-0008). The catalog, with the
posture per vector:

| Vector | Mechanics & cost | Defense |
|---|---|---|
| Idle-join farming | Join, do nothing, claim | Dead by design: 100 is not > 100 |
| Wash-trading ring | `k` verified accounts funnel points to their winners; near-free internally (fees on own arguments return to the ring) | Bounded to `(k−1)/N` of the pool; each seat costs a real personhood-verified identity |
| **Last-block snipe** | Redemption pays the final reserve ratio — the price the attacker set — so pushing a thin market from 50% to ~99% costs only the fee plus rounding. In the last block nobody can correct it, so the outcome is flippable for ~a fee | **Designated fix: time-weighted tally.** The tally reads the time-weighted approval over the rating window (one O(1) accumulator per argument); redemption keeps paying final reserves, so solvency is untouched. A snipe then moves the tallied rating by ~ε, and moving it materially requires holding a mispriced market all window — feeding correctors. TODO, tracked project-wide |
| Sustained manipulation | Hold a wrong price the whole window | Every token spent is profit for correctors; with the time-weighted tally this is the *only* way to attack, and it subsidizes the honest side |
| Argument spam / dilution | Min-deposit arguments dilute finalized siblings' weight (`childsVote` denominator), and the ≥50% seed floor means each enters contributing *positively* to its parent until down-rated; `MAX_ARGUMENTS = 1024` can be filled to lock out authors | Spam costs 10 per argument (10 max per solo participant); down-rating spam is *profitable* (the spammer's deposits are the pot); the cap-fill needs ~100 colluding identities. Residual risk: spam consumes honest raters' attention and budget |
| Bribery with external budget | Pay participants off-chain to rate a side | Out of scope by design — an equal-points game cannot out-secure external budgets larger than participants' stakes. This is exactly why the outcome is a signal, not a trigger (§6); §7 records what closing the gap would take |
| Hostile bounty token | Creator-controlled token: blacklist claimers, fee-on-transfer skimming, upgradeable rug | Uncurated by design; participants judge the token before investing effort. Implementation notes: balance-delta accounting on deposit, per-claimer pull payments so one blocked transfer cannot block others |
| Never tallied / never redeemed | Funds stuck if no one pokes | `tallyTree` is permissionless and bounty winners are motivated callers; stragglers only forfeit their own claim, bounded by the claim window |
| Creator self-play | Creator joins their own debate, wins, claims; also receives the remainder | Neutral: it is their own money circulating; they cannot suppress others' claims |
| Thesis framing | Negated or loaded thesis makes the boolean mean the opposite of what a consumer assumes | Social layer; consumers must bind to the thesis content digest, never to a debate id alone |

## 6. Consuming the outcome safely

Deliberate stays a pure deliberation primitive: quorum, delay, and veto live **consumer-side**. A
DAO executor (or any automation) gating value on `outcome(debateId)` should:

1. **Bind to the thesis**, not the id — check the debate's `contentURI` digest against the text the
   proposal was approved for.
2. **Require a quorum** — minimum participants and minimum `totalVotes` (a participants counter is a
   small contract addition, tracked as a TODO; total stake is already exposed).
3. **Require a margin** — the root's `descendantsImpact` magnitude, not just its sign.
4. **Timelock ≥ the claim window** — humans get one full window to inspect the tree, the claims,
   and the shape of late trading before anything irreversible executes.
5. **Keep a veto or challenge path** — e.g. a bonded challenge that forces a re-run debate before
   execution.

## 7. The road to oracle-grade (exploration)

ADR-0008 fixes the posture: deliberation-grade. This section records what closing the gap would
actually take, so the cost of "just trigger the funds off the boolean" is never underestimated —
and so the checklist exists if a consumer ever genuinely needs the trigger.

**The bar.** An oracle-grade outcome satisfies `cost-of-corruption ≥ value-at-stake`, where the
cost is measurable on-chain (a consumer must be able to verify the bound *before* executing) and
the inequality holds with no human backstop. Everything below follows from taking that inequality
seriously.

**Why the current game cannot reach it — four structural gaps.**

1. **Influence is priced in personhood, not capital.** Points are free and non-purchasable, so the
   money-cost of corruption is the off-chain price of bribing or renting verified humans — cheap
   (a dishonest rater forfeits at most a speculative bounty claim; nothing else is at stake) and
   fundamentally unquantifiable on-chain. No sound value bound can even be *stated*, let alone
   checked by a consumer. Quantifiable security requires influence priced in an asset the contract
   can see.
2. **Settlement is self-referential.** Redemption pays the final rating itself; there is no
   exogenous event against which a manipulator is later proven wrong and slashed. Prediction
   markets derive manipulation-resistance from an external resolution criterion — manipulators
   subsidize informed traders who profit *when reality settles the market*. Rating markets are
   their own resolution, so "reality" never arrives to punish a sustained lie.
3. **The game is one-shot.** A wrong outcome is final. Every oracle-grade system makes the first
   answer merely *provisional*: an escalation game (bonded challenges, appeal rounds) multiplies
   the capital at risk until corruption becomes unprofitable. Crucially, escalation must *change
   the game* — re-running the same equal-points debate at higher volume replays the same
   corruptibility.
4. **Actions are public and provable.** Every stake is visible on-chain, so a briber can verify
   compliance — the precondition for the p + ε class of attacks, where *conditional* side-payments
   (paid only if the bribed side loses) corrupt a coherence-rewarded game at near-zero cost in
   equilibrium.

**The required ingredients** — each maps to a system that paid its cost:

- **(a) Capital at risk, open entry.** Influence must be purchasable so that outweighing honest
  capital costs real money (futarchy, Augur-style markets). This directly abandons the
  one-human-one-budget principle — at the settlement layer, oracle-grade *is* coin-weighted.
- **(b) Optimistic execution with bonded escalation.** Outcomes execute only if unchallenged for a
  window; each challenge roughly doubles the stakes (UMA's optimistic oracle, Kleros appeals).
- **(c) An anchored court of last resort.** The terminal layer's honesty must be backed by
  slashable value at least equal to the maximum value ever protected: a token-holder vote (UMA's
  DVM), a final all-juror round (Kleros), or a fork in which the dishonest branch's token goes to
  zero (Augur). In every known design this means **a protocol token whose defendable market
  capitalization is the security budget** — or an explicit dependency on someone else's
  (Kleros/UMA/an external arbitrator).
- **(d) Bribery resistance.** Unprovable actions (MACI-style secret ballots, where a participant
  cannot prove to a briber how they acted) or fork-based subjectivocracy as the ultimate defense.
  Public AMM stakes are inherently bribable-with-proof — this ingredient conflicts with the very
  transparency that makes the argument tree auditable.
- **(e) A value cap at the consumer.** Even with all of the above: execute only
  `V ≤ α × (measured corruption cost)`, with α ≪ 1.

**The minimal wrapper, sketched.** Deliberate itself stays the deliberation primitive (ADR-0005 —
no in-protocol disputes — stays intact); oracle-grade would be a *separate consumer contract*:
outcome → challenge window → anyone bonds `B` to veto → escalation hands the question to an
anchored resolver (external arbitrator or token court), the bond forfeited against the resolution.
Note what this admits: the debate's tally becomes an **advisory input** to the resolver of last
resort — the oracle-grade answer is ultimately produced by the anchor, not by the debate. The
debate's role is to make the honest answer *cheap to defend* (the evidence tree is already built)
and dishonest challenges expensive.

**Verdict.** Ingredients (a)–(d) amount to building or importing a second protocol and abandoning
the egalitarian principle at the settlement layer. That is why ADR-0008 chooses the signal posture.

## 8. The sybil gate

Every attack bound above is denominated in *identities* — the `(k−1)/N` collusion cap, the
wash-ring cost, the spam economics all assume one human cannot join twice. The gate carrying that
assumption is deliberately minimal and pluggable: `join` queries an
[`IIdentityRegistry`](../src/interfaces/IIdentityRegistry.sol) —
`isRegistered(address) → bool` — fixed per deployment. No live EIP standardizes this query
(ERC-725/735 are heavyweight claim frameworks, EAS is infrastructure rather than a standard); the
interface generalizes the Proof of Humanity v1 registry shape, and concrete providers plug in behind
adapters:

- **Designed-for primary shape: nullifier-based ZK personhood.** One human proves uniqueness once
  and registers one address per scope without revealing which human — **World ID (Orb-level)** as
  the flagship where its verifier is reachable, the **zk-passport family (Self, zkPassport,
  Rarimo)** as the credential-based alternative.
- **Pragmatic Base-native fallback: Coinbase Verifications** — an externally operated KYC registry
  ("Verified Account" EAS attestations on Base) matching the old registry shape behind the
  reference adapter [`EASIdentityRegistry`](../src/adapters/EASIdentityRegistry.sol) (configured
  attester + schema + indexer, revocation/expiry checked). Non-private (the account↔person link
  sits with Coinbase), and the deciding caveat: **deduplication is only as strong as the provider's
  per-identity address policy** — whether one Coinbase account can attest several addresses is
  exactly the one-human-one-join question, and there is deliberately no public cross-address human
  ID to check. Verify the attester, schema UID, indexer address, and that policy against the
  official publications before relying on it.
- **Development: `MockIdentityRegistry`** (everyone registered, per-address deny toggle) on local
  chains and test networks.

Whatever the provider, the gate only prices sybils at "one more verified identity"; bribing *real*
humans stays out of scope by design (§5, §7).

## 9. Open questions

- **Protocol fee** — none in v1; revisit later, possibly as part of the market-fee mechanism.
- **Market fee level (5%) and deposit floor (10)** — tune with usage data (existing TODO).
- **Time-weighted tally** — the designated snipe fix (§5); needs the accumulator design.
- **Participants counter + getter** — needed by the payout denominator and by consumer quorums.
- **Per-debate join fee** — a future creator-option knob: a flat ERC-20 toll flowing *into* the
  bounty pool, so sybil rings feed the prize they attack. Rejected for v1 (prices out honest
  participants, couples joining to the bounty token).
- **Per-debate allowlist** — a creator-configured join gate (instead of, or on top of, personhood)
  for DAO- or community-scoped debates: strong sybil control for high-stakes questions, at the cost
  of the open "anyone can argue" default — so strictly a per-debate opt-in, visible in the UI. Also
  bounds and pre-announces `N`, sharpening the payout denominator and consumer quorums. Tracked in
  the project TODO.
- **Deposit-as-position** — letting the author's deposit buy shares at their seeded rating would
  make authoring recoverable-if-right and seeding honest, but it drains the exact subsidy that makes
  rating profitable in consensus debates. Documented as an alternative, not planned.
- **In-module vs. wrapper contract** — whether the bounty layer lives in `Deliberate` or in a
  separate vault referencing debates; implementation placement, orthogonal to the rules above.
