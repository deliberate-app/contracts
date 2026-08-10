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
  fee**: the debate's fee percentage (creator-chosen at creation, 0–99%, see ADR-0010) of every
  stake on their argument, claimable as vote tokens once the debate is finished. Break-even is
  `(100 / fee) × deposit` in stake volume — `20 × deposit` at a 5% fee.
- **Raters** stake tokens on a market's pro or con side and profit at redemption if the final rating
  moved their way beyond their own trade. Two facts shape this: the fee means only mispricings
  larger than roughly the fee percentage are worth correcting, and the **self-impact limit** — you
  cannot profit from the price move you yourself cause — means profit requires either _other raters
  being wrong_ or _mispriced seeded reserves_.

Together this is a deliberate **two-sided payment loop**: authors pay raters (the sunk deposit in
mispriced reserves is the pot that makes rating profitable even in a consensus debate), and raters
pay authors (the fee rewards arguments that attract rating volume). A "wrong" seeded approval is not
a defect — it is the subsidy that makes verifying the rating worthwhile. The balance knob between
the two sides is `fee % × expected volume` versus `deposit`, tracked in the project TODO as a
tune-with-data parameter. Honest caveat: in small, quiet debates authorship is net-negative — the
bounty layer (fees count toward excess) is what tops it up.

## 2. Why anyone participates (without a bounty)

- **The creator** gets the thesis adversarially tested: a tree of weighted, market-rated arguments
  and an outcome. The value is the _tested_ answer, not the answer alone.
- **Authors** earn fees and sway the outcome — a well-placed argument recruits the whole tree
  beneath it.
- **Raters** earn trading profit from mispricings and move ratings toward their view.

These motives are real but thin at small scale; the bounty layer exists to pay for the work.

## 3. The bounty layer (planned)

The creator attaches a prize in an ERC-20 of their choosing; participants who _net win_ vote tokens
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
always ≤ 100 — so "above average" would let a verified human join, do _nothing_, sit at exactly 100
above the mean, and claim. Attaching money to that makes idle-joining the dominant strategy. The
average is also not computable on-chain until every participant has redeemed and claimed, which no
one can force. `tokens > 100` kills both problems and is a constant-time check.

**Fixed denominator `100·N`, not `Σ excess`.** Pro-rata over total excess would always pay out the
whole pool — but total excess is unknowable until global settlement (two-phase machinery), and a
wash-trading coalition would capture its share of the _whole_ pot however small the honest activity.
Against the fixed denominator, a coalition of `k` participants funneling their own points to their
winners manufactures at most `100·(k−1)` excess — **at most `(k−1)/N` of the pool**, paid for in
real verified identities.

**The remainder is the point, not a bug.** The claimed fraction `c = Σ excess / (100·N)` measures
exactly how much capital changed hands — how contested the debate was and how wrong the losing side
was. Expected magnitudes:

| Debate character                                   | Claimed `c` | Remainder |
| -------------------------------------------------- | ----------- | --------- |
| Consensus (seeds near truth, raters agree)         | ~1–5%       | ~95–99%   |
| Genuinely contested (≈60% deployed, a third wrong) | ~15–25%     | ~75–85%   |
| Polarized blowout                                  | ~30–50%     | ~50–70%   |
| Adversarial ceiling (one account sweeps all)       | → ~100%     | → 0       |

The creator therefore posts a **maximum** prize and pays in proportion to the disagreement actually
resolved — posting a generous bounty on a question you believe settled is cheap, and it becomes
expensive precisely when real information surfaces. Drivers of `c`: wrong-way capital (dominant),
fee volume to authors, deposit capture by raters; reduced by leakage; inflated by collusion up to
the headcount bound above.

## 5. Attacks on the bounty and the outcome

The outcome (`descendantsImpact > 0` at the root; a tie reads as objected — fail-safe) is a
**credible deliberation signal, not a manipulation-proof oracle** (ADR-0008). The catalog, with the
posture per vector:

| Vector                                    | Mechanics & cost                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Defense                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Idle-join farming                         | Join, do nothing, claim                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Dead by design: 100 is not > 100                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Wash-trading ring                         | `k` verified accounts funnel points to their winners; near-free internally (fees on own arguments return to the ring)                                                                                                                                                                                                                                                                                                                                                                                            | Bounded to `(k−1)/N` of the pool; each seat costs a real personhood-verified identity                                                                                                                                                                                                                                                                                                                                                              |
| **Last-block snipe**                      | Redemption pays the final reserve ratio — the price the attacker set — so pushing a thin market from 50% to ~99% costs only the fee plus rounding. In the last block nobody can correct it, so the outcome is flippable for ~a fee                                                                                                                                                                                                                                                                               | **Designated fix: time-weighted tally.** The tally reads the time-weighted approval over the rating window (one O(1) accumulator per argument); redemption keeps paying final reserves, so solvency is untouched. A snipe then moves the tallied rating by ~ε, and moving it materially requires holding a mispriced market all window — feeding correctors. TODO, tracked project-wide                                                            |
| Sustained manipulation                    | Hold a wrong price the whole window                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Every token spent is profit for correctors; with the time-weighted tally this is the _only_ way to attack, and it subsidizes the honest side                                                                                                                                                                                                                                                                                                       |
| Argument spam / dilution                  | Min-deposit arguments dilute finalized siblings' subtree-stake shares (ADR-0011), and the ≥50% seed floor means each enters contributing _positively_ to its parent until down-rated; `MAX_ARGUMENTS = 1024` can be filled to lock out authors                                                                                                                                                                                                                                                                   | Spam costs 10 per argument (10 max per solo participant); down-rating spam is _profitable_ (the spammer's deposits are the pot); the cap-fill needs ~100 colluding identities. Residual risk: spam consumes honest raters' attention and budget                                                                                                                                                                                                    |
| **Weight stuffing via self-rated decoys** | Stake is voice (ADR-0011), and volume at the price extremes round-trips nearly free: attach a garbage argument to the side you _oppose_, then buy the side that redeems near 1 (crashing your own decoy) — fees return to you as its creator, principal redeems at ~face value, net cost ≈ the 10-token deposit. The decoy's ~100-token subtree weight dilutes its genuinely strong siblings' shares, and correctly down-rating it fixes the _price_ while _feeding the weight_ — correction cannot remove stake | Open. The cost is real but small (deposit + locked-capital opportunity + curve rounding), and unlike spam the decoy's rating is _meant_ to be crashed. Likely fix direction: extend the time-weighted tally (above) to the **weights** — weight from stake held through the window, so stuffing pays a full window of exposure. Any mechanism that attracts stake to chosen arguments (e.g. per-argument bounties, §11) industrializes this vector |
| Bribery with external budget              | Pay participants off-chain to rate a side                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Out of scope by design — an equal-points game cannot out-secure external budgets larger than participants' stakes. This is exactly why the outcome is a signal, not a trigger (§6); §7 records what closing the gap would take                                                                                                                                                                                                                     |
| Hostile bounty token                      | Creator-controlled token: blacklist claimers, fee-on-transfer skimming, upgradeable rug                                                                                                                                                                                                                                                                                                                                                                                                                          | Uncurated by design; participants judge the token before investing effort. Implementation notes: balance-delta accounting on deposit, per-claimer pull payments so one blocked transfer cannot block others                                                                                                                                                                                                                                        |
| Never tallied / never redeemed            | Funds stuck if no one pokes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `tallyTree` is permissionless and bounty winners are motivated callers; stragglers only forfeit their own claim, bounded by the claim window                                                                                                                                                                                                                                                                                                       |
| Creator self-play                         | Creator joins their own debate, wins, claims; also receives the remainder                                                                                                                                                                                                                                                                                                                                                                                                                                        | Neutral: it is their own money circulating; they cannot suppress others' claims                                                                                                                                                                                                                                                                                                                                                                    |
| Thesis framing                            | Negated or loaded thesis makes the boolean mean the opposite of what a consumer assumes                                                                                                                                                                                                                                                                                                                                                                                                                          | Social layer; consumers must bind to the thesis content digest, never to a debate id alone                                                                                                                                                                                                                                                                                                                                                         |

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
cost is measurable on-chain (a consumer must be able to verify the bound _before_ executing) and
the inequality holds with no human backstop. Everything below follows from taking that inequality
seriously.

**Why the current game cannot reach it — four structural gaps.**

1. **Influence is priced in personhood, not capital.** Points are free and non-purchasable, so the
   money-cost of corruption is the off-chain price of bribing or renting verified humans — cheap
   (a dishonest rater forfeits at most a speculative bounty claim; nothing else is at stake) and
   fundamentally unquantifiable on-chain. No sound value bound can even be _stated_, let alone
   checked by a consumer. Quantifiable security requires influence priced in an asset the contract
   can see.
2. **Settlement is self-referential.** Redemption pays the final rating itself; there is no
   exogenous event against which a manipulator is later proven wrong and slashed. Prediction
   markets derive manipulation-resistance from an external resolution criterion — manipulators
   subsidize informed traders who profit _when reality settles the market_. Rating markets are
   their own resolution, so "reality" never arrives to punish a sustained lie.
3. **The game is one-shot.** A wrong outcome is final. Every oracle-grade system makes the first
   answer merely _provisional_: an escalation game (bonded challenges, appeal rounds) multiplies
   the capital at risk until corruption becomes unprofitable. Crucially, escalation must _change
   the game_ — re-running the same equal-points debate at higher volume replays the same
   corruptibility.
4. **Actions are public and provable.** Every stake is visible on-chain, so a briber can verify
   compliance — the precondition for the p + ε class of attacks, where _conditional_ side-payments
   (paid only if the bribed side loses) corrupt a coherence-rewarded game at near-zero cost in
   equilibrium.

**The required ingredients** — each maps to a system that paid its cost:

- **(a) Capital at risk, open entry.** Influence must be purchasable so that outweighing honest
  capital costs real money (futarchy, Augur-style markets). This directly abandons the
  one-human-one-budget principle — at the settlement layer, oracle-grade _is_ coin-weighted.
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
no in-protocol disputes — stays intact); oracle-grade would be a _separate consumer contract_:
outcome → challenge window → anyone bonds `B` to veto → escalation hands the question to an
anchored resolver (external arbitrator or token court), the bond forfeited against the resolution.
Note what this admits: the debate's tally becomes an **advisory input** to the resolver of last
resort — the oracle-grade answer is ultimately produced by the anchor, not by the debate. The
debate's role is to make the honest answer _cheap to defend_ (the evidence tree is already built)
and dishonest challenges expensive.

**Verdict.** Ingredients (a)–(d) amount to building or importing a second protocol and abandoning
the egalitarian principle at the settlement layer. That is why ADR-0008 chooses the signal posture.

## 8. The sybil gate

Every attack bound above is denominated in _identities_ — the `(k−1)/N` collusion cap, the
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

Whatever the provider, the gate only prices sybils at "one more verified identity"; bribing _real_
humans stays out of scope by design (§5, §7).

## 9. What a live agent run showed (2026-08-10)

The first live multi-agent run — ten LLM agents on Base Sepolia, debate 3, thesis _"Humans should act
to fight climate change."_, 5% fee, 10 EURC bounty, 60-minute editing / 30-minute rating — produced
the first behavioural evidence about these incentives. **Read it as one observation, not a result:**
one thesis, one parameter set, `N = 10`, and agents that are language models rather than people.

The run ended in a way that is itself the headline. Editing worked: 48 arguments, three levels deep.
Rating did not happen — the agents' language-model budget was exhausted partway into the phase and
the population stopped acting after **three stakes**. The debate was tallied and closed by hand
afterwards. So §§9.1–9.5 rest on a full editing phase and are solid; §§9.6–9.7 describe a rating
phase that barely began, and are pointers for the next run rather than findings.

**9.1 Supporting sub-arguments are dominated; attacks have no substitute.** Every one of the 32 arguments below the
top level attacked its parent — without exception:

| depth | supports | attacks |
| ----- | -------- | ------- |
| 1     | 13       | 3       |
| 2     | 0        | 26      |
| 3     | 0        | 6       |

This is not a mechanical dead end: `_tallyNode` folds a child in as `isSupporting ? impact : -impact`,
so the two directions are symmetric in the tally. The asymmetry is in the _alternatives_. To push the
thesis one way, a top-level argument folds straight into the root at full subtree weight, while a
supporting child reaches the root only through its parent's weighted mean — diluted by the parent's
own votes and by every sibling, for the same deposit. Agreeing therefore has two better moves (post
your own top-level claim, or stake the argument up), while _reducing one specific argument's weight_
has no substitute at all: attaching an attack is the only structural option.

That the same agents chose supports 12:3 at depth 1 — where supporting _is_ the direct move — is what
suggests the pattern is structural rather than models defaulting to rebuttal.

Consequence for a reader of the tree: **it records objections richly and corroboration not at all.**
"What else supports this claim?" has no representation below the root. Note this does _not_ bias the
outcome in one direction — the sign alternates with depth, so an attack on an anti-thesis argument
raises the thesis. The open question is whether a tree that cannot express corroboration is the
intended epistemic object, or whether supporting children need a reason to exist that the current
weighting does not give them.

**9.2 Authoring and rating draw on one budget, and authoring won.** The 100 tokens fund both roles,
and nothing rations them across phases. By the end of editing:

|              | tokens left |
| ------------ | ----------- |
| author-con-2 | 9           |
| author-pro-1 | 11          |
| author-con-1 | 13          |
| creator      | 15          |
| author-pro-2 | 25          |
| raters       | 73–85       |

The role split was never assigned; it fell out of deposits costing tokens. By the end of rating the
separation was total:

|                                            | final tokens |
| ------------------------------------------ | ------------ |
| raters                                     | 48–85        |
| creator                                    | 15           |
| author-con-1 / author-pro-2 / author-pro-1 | 3 / 2 / 1    |
| author-con-2                               | **0**        |

**Every author spent itself to zero.** Not "entered rating with less" — four of the five authoring
agents finished the debate unable to place even a minimum stake, and one could no longer author
either. This is the trap rather than the specialization: an author who cannot rate cannot defend its
own argument's price, and fee revenue only arrives _after_ the debate is finished, so there is no
in-debate feedback loop that would have told them to stop. Nothing in the mechanism rations the 100
tokens across the two phases, and nothing warns an author approaching the floor.

The lever is not obviously "raise the grant" — a larger grant spent the same way reaches the same
place. Candidates worth testing: reserving a fraction of the grant for the rating phase, making
deposits partially refundable at redemption, or surfacing the remaining budget against the phase
clock so the trade-off is visible at the moment of decision (§9.4 suggests visibility is what
actually steers these agents).

**9.3 The deposit floor is the de facto deposit, and seeds cluster.** Every deposit was 10, 12, or 15
against a floor of 10 and no ceiling; 23 of 44 seeds were priced at exactly 65% against a permitted
50–99%. Under ADR-0011 the deposit is an argument's *starting* tally weight — every later stake adds to
it — so a population that all bids the floor starts every argument at the same weight, and the
authors' half of the weight lever goes unused. In this run rating then barely happened (§9.6), so
the flat start was also nearly the final weight distribution. The floor is not just a spam price; it is
a focal point that suppresses the weight signal it was meant to carry.

**9.4 The agents reasoned about the mechanism in front of them, not the payoff.** Across 224 stated
reasons attached to their actions:

| theme                                  | share of reasons |
| -------------------------------------- | ---------------- |
| price / mispricing                     | 25%              |
| locking windows and timing             | 32%              |
| what other participants are doing      | 12%              |
| market fees (the author revenue model) | 1%               |
| their own token budget                 | 1%               |
| **the bounty**                         | **0%**           |

The bounty is the entire reason the run is funded and it never entered a single stated decision;
fees, the authors' only revenue, entered four times out of 224. Agents optimized what the interface
put in front of them — approvals, clocks, rivals — and ignored the terminal payoff. 9.2 follows
directly: nobody budgets for a phase they are not reasoning about. If this reproduces with human
participants, it is an interface finding as much as an incentive one: **a payoff that is not visible
at the moment of decision does not steer behaviour**, however well it is specified.

**9.5 Self-dealing was discovered unprompted.** Two agents independently reasoned toward staking on
their own arguments — _"fee-efficient since I'm the author"_ and _"with author fees flowing back to
me"_ — without any prompt describing the tactic. This is the cheap end of the weight-stuffing vector
in §5, found by inspection of the rules alone within one hour.

**It was never executed.** All three stakes the run produced went to _other_ authors' arguments; the
agents that reasoned toward self-dealing ran out of tokens (§9.2) before the rating phase they were
planning for. So the finding is about discoverability, not profitability: the tactic is reachable by
reading the rules, and the only thing that stopped it here was bankruptcy. Whether the round-trip
actually pays at a 5% fee remains untested and is the first thing the next run should measure — it
is the vector §5 marks "open".

**9.6 Rating never priced the tree, and the outcome came from the seeds.** Three stakes landed
before the population went quiet. Their distribution is the interesting part:

| argument                       | stake                                      | final approval                    |
| ------------------------------ | ------------------------------------------ | --------------------------------- |
| 1 (first argument posted)      | 34 tokens across 2 stakes, plus one attack | 93%                               |
| every other top-level argument | none                                       | 60% — the seeded price, untouched |

Two of the three stakes went to argument 1, which finished with 48 votes against 15 for everything
else. The market that formed was a _first-mover_ market: the earliest argument accumulated nearly
all the attention, and forty-odd later arguments were never priced at all.

The consequence for the outcome is the one to sit with. `outcome(3)` returned **true** — the thesis
confirmed — but with 45 of 48 markets sitting exactly at their authors' seeded prices, that verdict
was produced almost entirely by _what authors claimed their own arguments were worth_, corrected by
three trades. The tally is only a deliberation signal when rating actually happens; a debate where
it does not is closer to a poll of authors. §6's advice to require a quorum should therefore be read
as covering **stake volume**, not just participant count — this run would have passed a headcount
quorum comfortably while carrying almost no rating information.

**9.7 The bounty paid nothing, exactly as specified.** Zero of the 10 EURC was claimed, because
eligibility requires ending strictly above the 100-token grant (§4) and nobody did: with three
stakes there was almost no trading, so no tokens moved between participants and nobody accumulated
excess. This is the `c ≈ 0` corner of the §4 table — a debate that resolved no disagreement pays out
nothing and the creator sweeps the pool after the claim window. The mechanism behaved correctly
under a degenerate run, which is worth knowing, but it also means **a bounty cannot rescue a debate
that fails to trade**: the prize only pays for disagreement actually resolved, so a creator whose
debate stalls gets their money back rather than the answer they wanted.

**9.8 Operating cost is a live constraint on the mechanism, not just on the experiment.** The run
died because its agents' language-model budget ran out mid-rating — the editing phase, which is
cheap for the protocol, is expensive for anything automating participation. Any future in which
agents participate at scale inherits this: authoring is a few decisions, while rating well means
reading and pricing every argument in a growing tree, so per-participant cost rises with tree size
exactly when rating matters most. That pressure points the same way as the economics in §9.6 —
toward participants who price a handful of prominent arguments and ignore the tail.

## 10. The participation problem, in the abstract

§9 ends in a payout of zero, and §4 shows that was the rules working. This section states the
underlying problem precisely, finds its names in the mechanism-design literature, and lists the
instruments that literature offers — because the problem is structural, not a tuning miss.

**10.1 The abstract mechanism.** Strip the debate away. `N` participants each receive an endowment
`E` of a non-transferable internal currency. The internal game is redistributive: tokens only move
between participants, so `Σ xᵢ ≤ E·N` (minus leakage) whatever happens. An external reward pool `R`
pays each participant `R·(xᵢ − E)⁺ / (E·N)` — a payment on the *positive part* of their net win.
Participation costs every participant a real `cᵢ > 0` (time, attention, and §9.8's compute).

Three consequences follow from the structure alone:

1. **The pool pays for dispersion, not for information.** Total payout is `R·Σ(xᵢ−E)⁺/(E·N)` —
   §4's claimed fraction `c` — and `Σ(xᵢ−E)⁺` is bounded by the losers' shortfall. It measures how
   *spread out* final balances are, nothing else. A debate can do maximal epistemic work with zero
   dispersion: if everyone prices correctly, nobody nets tokens off anyone, and the pool pays
   nothing. §9.6–9.7 realized exactly this corner.
2. **The representative participant earns less than nothing.** The internal game is zero-sum, so
   `E[xᵢ] ≤ E` for a symmetric participant, and the bounty term is a call option on a zero-mean
   redistribution — its expected value is a variance premium, not a wage. Net of `cᵢ` the
   participation constraint fails for the median type: **the mechanism pays the upper tail of a
   redistribution whose mean is the endowment you walked in with.**
3. **Entry unravels.** Only those who believe they are above median enter — the overconfident and
   the genuinely informed. But if only informed, rational participants enter, the
   [no-trade theorem](https://en.wikipedia.org/wiki/No-trade_theorem) (Milgrom–Stokey 1982) applies:
   equally informed rational agents will not take the other side of each other's zero-sum bets, so
   volume → 0, dispersion → 0, payout → 0 — confirming the decision not to enter. The three stakes
   of §9.6 are this equilibrium observed, not an anomaly of language models.

The crux, stated once: **payment is proportional to residual disagreement, and deliberation's goal
state is the elimination of disagreement — so the mechanism defunds its own success.** The better
the debate works, the closer its payout is to zero.

**10.2 What the literature calls this.** Three bodies of work describe the pieces:

- *Budget-balanced wagering.* The internal game is a
  [wagering mechanism](https://www.sciencedirect.com/science/article/abs/pii/S0022053114000520)
  (Lambert et al.): truthful and individually rational, but weakly budget-balanced — a mechanism in
  which, if one agent can gain, another must lose, and whose symmetric-belief equilibrium pays
  everyone zero. The literature's own conclusion is that such mechanisms need an external subsidy
  to pay for participation, and that making them ex-post safe for everyone (nobody can lose)
  invites sybils — the same tension as §8.
- *Contest and tournament theory.* The bounty is a rank-order prize on the redistribution's upper
  tail. Winner-take-all-shaped prizes are known to deter entry of risk-averse and lower-ability
  types; [Moldovanu–Sela (2001)](https://www.econ.uni-bonn.de/micro/en/moldovanu/publications-1/pearson22.pdf/@@download/file/pearson22.pdf)
  show multiple descending prizes dominate under convex costs or
  [risk aversion](https://www.sciencedirect.com/science/article/abs/pii/S0899825621000907), and
  [experiments on entry](https://www.sciencedirect.com/science/article/abs/pii/S0047272710000526)
  find proportional prizes attract systematically more participation than winner-take-all. Rank
  incentives also distort reports toward extremes
  ([Witkowski et al.](https://arxiv.org/pdf/2101.01816) formalize incentive-compatible forecasting
  competitions because of it).
- *Market microstructure.* A zero-sum market functions only with noise traders or a subsidy.
  Deliberate already knows this — §1's "the mispriced seed is the subsidy" — but assigns the noise
  trader role to *authors*, whose deposits are forced, negative-expectation liquidity. §9.2 shows
  where that leads: the subsidizers go bankrupt first.

**10.3 The instruments, mapped.** Every known fix converts some relative-performance pay into
subsidized absolute-performance pay — the differences are in what "absolute performance" means and
what the subsidy's loss bound is:

| Instrument | Pays for | Loss bound | Fit |
|---|---|---|---|
| [Subsidized market maker](https://courses.cs.duke.edu/spring17/compsci590.2/market_scoring.pdf) (Hanson's LMSR) | Moving a price toward its final value | Fixed `b·ln(outcomes)` per market | Replace the author's sunk deposit as market seed with bounty-funded reserves at a deliberately uninformative price: every correction toward the tallied rating becomes positive-EV, authors stop being the forced noise traders, and the creator's maximum loss stays bounded as today |
| Per-report [proper scoring](https://arxiv.org/pdf/2101.01816), pool-normalized | Accuracy of each stake against the final tallied rating, paid pro-rata from `R` | `R` exactly | A proportional-prize contest: everyone with a positive score earns something, entry improves (the experimental result above), and the §4 denominator logic survives as normalization. Self-referential: "accuracy" means agreement with the crowd's final price |
| [Peer prediction / BTS](https://cdn.aaai.org/ojs/8261/8261-13-11789-1-2-20201228.pdf) (Miller–Resnick–Zeckhauser, Prelec, robust variants) | Reports that are informative about *other* reports — no ground truth needed | `R` (designed positive-sum) | Matches the protocol's deepest constraint: settlement is self-referential (§7 gap 2), and peer prediction is the branch of elicitation built for exactly that. Known weak point is sybils, which §8's gate already prices |
| Multiple / proportional prizes, participation floor ([contest theory](https://marketing.wharton.upenn.edu/wp-content/uploads/2016/10/Kireyev-Pavel-JMP-Prize-Allocation-and-Entry-in-Ideation-Contests.pdf)) | Rank, but with full-support payouts; optionally a base payment for scored activity | `R` | Cheapest patch to the existing rules: split `R` into a pro-rata-on-scored-activity floor and an excess prize. Must pay *scored* activity, never raw volume — raw-volume pay is §5's rejected per-argument bounty |
| Mildly positive-sum points ([Metaculus](https://metaculus.medium.com/aligning-incentives-for-forecast-accuracy-relevance-and-efficacy-a-new-paradigm-for-metaculus-26b0e79616cb)) | Proper-score accuracy, deliberately positive-sum | Platform-chosen | The applied precedent: a forecasting platform that moved off pure relative scoring explicitly to keep participation |

**10.4 The honest trade-off.** §4 chose excess-only pay *for* its manipulation bounds: the
`(k−1)/N` collusion cap and the idle-join kill both come from paying nothing unless tokens moved.
Every instrument above spends some of that safety to buy participation — a positive-sum payment for
"being right" in a self-referential market is, to a coalition, a payment for manufacturing the
final price (§5's herding and wash vectors). The instruments with *structural* loss bounds (LMSR's
`b·ln(n)` per market; pool-normalized scoring's exactly-`R`) preserve bounded exposure, and
accuracy-weighting preserves the principle that raw activity earns nothing. What no instrument
preserves is `c ≈ 0 ⇒ payout ≈ 0` — that property *is* the participation problem, and the design
has to give it up deliberately rather than lose it by accident.

One distinction keeps this consistent with §11's rejection of per-argument bounties (below): those
paid for *stake volume on a chosen argument* — purchasable, sybil-linear, weight-buying. An LMSR
subsidy or accuracy-normalized payout pays only for *price improvement toward the final rating* —
volume at the final price earns exactly zero. The vector §5 industrializes is not reopened by
paying for corrections; it is reopened by paying for flow.

## 11. Open questions

- **Protocol fee** — none in v1; revisit later, possibly as part of the market-fee mechanism.
- **Per-argument bounties — considered and rejected (2026-07-22).** Creator-funded ERC-20 prizes on
  individual markets, and fee-scored debate-bounty shares for authors, both score _stake volume_ —
  which round-trips nearly free at the price extremes, is sybil-linear, and (since ADR-0011)
  purchases tally weight, bridging external money into influence the vote-token design exists to
  keep non-purchasable. The incentive-clean equivalents already exist: the **deposit** is the
  argument-level prize (extractable only by correcting the price), authors already compete for the
  debate bounty **through fees driving excess**, and anyone can subsidize a debate via `fundBounty`
  top-ups. The UI surfaces each market's upside (its reserves — the mechanism-exact bound on what
  correcting it can free) as the attention beacon instead.
- **Deposit floor (10)** — tune with usage data (existing TODO). The market fee level is no longer
  a protocol constant to tune — debate creators choose it per debate (ADR-0010); what remains
  observable is which fees debates actually pick.
- **Time-weighted tally** — the designated snipe fix (§5); needs the accumulator design.
- **Participants counter + getter** — needed by the payout denominator and by consumer quorums.
- **Per-debate join fee** — a future creator-option knob: a flat ERC-20 toll flowing _into_ the
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
