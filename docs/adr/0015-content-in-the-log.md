---
status: accepted
date: 2026-09-02
---

# Argument content is published in the log, not stored or content-addressed

Until now the chain held a 32-byte sha-256 digest per argument (a full storage slot) and the text
lived on IPFS as a raw-leaves block whose CID wraps exactly that digest: the frontend pinned it
through an authenticated proxy at authoring time, the indexer re-pinned everything it saw, and every
read fetched from a gateway and hashed the bytes back to the digest. The digest was kept off the
event log deliberately (2026-09-01): on Ethereum mainnet a 256-byte log costs real money per
argument, and that was weighed against a digest the chain would store either way.

The scheme worked and it verified, but it carried a standing cost: a gateway serves a fresh CID in
seconds to tens of seconds until a provider is found, so the first reader of every argument waited;
a pinning account and its secrets had to be guarded against becoming a free CDN; the soundness of
the whole arrangement rested on one encoder detail (raw leaves, single block, no re-chunking); and
the resolution code existed three times over.

## Decision

`createDebate`, `createArgument`, and `alterArgument` take the text itself as `string calldata`, 1 to
256 bytes of UTF-8 (`Parameters.MAX_CONTENT_LENGTH`), and publish it in `DebateCreated`,
`ArgumentCreated`, and `ArgumentAltered`. The contract stores none of it and never reads it:
`Argument.Data` lost its content slot, and the latest of an argument's events is its text.

Readers take content from the log. The indexer folds the events and serves the text with the rest
of the tree; a reader without an indexer (the frontend's chain fallback, the agents) runs
`eth_getLogs` from the deployment block.

## Consequences

- **Cheaper on every chain, mainnet included.** The slot the digest occupied cost 22,100 gas on every
  argument; the text costs about 8 gas per byte in the log plus 16 per byte of calldata, some 1,700
  gas for a typical 70-byte argument and 6,700 at the cap. The chain the digest was kept for is the
  chain where the saving is largest.

- **No content addressing, no verification against a digest.** A reader trusts its indexer for the
  text exactly as it already trusts it for reserves and stakes; the log is the source of truth and
  anyone can rebuild it from a node. Nothing in state binds a consumer contract to a thesis: a
  proposal names the debate by its id, which is unique and never changes, and quotes the thesis the
  consumer vetted. ADR-0008 and `incentives.md` §6 are amended accordingly.

- **Content is chain history.** There is no unpinning; a text can only be filtered out of a display,
  and the cap bounds what a transaction can carry. In return a wallet shows the signer the text they
  are publishing, not a digest.

- **The cap is bytes.** Clients count UTF-8 bytes, not characters, and reject before sending: a
  revert is the expensive way to learn the limit.

- Deployed contracts are immutable (ADR-0006): ships as a new deployment, and its readers change
  with it (indexer schema and handlers, frontend, agents).
