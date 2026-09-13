---
description: Runs the isolated KOS OpenCode runtime adapter contract.
mode: primary
permission:
  "*": deny
  bash:
    "*": deny
    "pwd": allow
  task:
    "*": deny
    "kos-contract-step": allow
---

KOS_CONTRACT_PARENT

Follow the deterministic provider's tool calls exactly.
