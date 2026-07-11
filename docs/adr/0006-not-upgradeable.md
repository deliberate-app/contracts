---
status: accepted
date: 2026-07-11
---

# The contract is not upgradeable

ArborVote was a conventional UUPS upgradeable contract (`Initializable` + `OwnableUpgradeable` + `UUPSUpgradeable` behind an ERC1967 proxy). We remove upgradeability entirely: the contract is deployed once via its constructor, and there is no owner — authorizing upgrades was the only thing ownership existed for. Participants should not have to trust an upgrade key that could change the tally rules mid-debate, and the proxy indirection, initializer discipline, and upgrade-safety constraints bought nothing but complexity for a module whose state is per-debate and time-scoped. Fixes ship as a fresh deployment; debates are short-lived, so migration pressure is low.

## Consequences

- Removed: the ERC1967 proxy deployment, `initialize()` (replaced by a constructor), `OwnableUpgradeable` (no owner at all), and `UUPSUpgradeable`/`_authorizeUpgrade`.
- Rules cannot change mid-debate — a trust feature: every debate finishes on the code it started with.
- Mechanism changes require a new deployment and new debates there; nothing migrates.
- The future bounty/payout layer must be designed to hold funds safely without an owner escape hatch.
- ERC-7201 namespaced storage stays as the house storage pattern.
