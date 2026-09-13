---
description: Acts as the isolated KOS workflow-step contract child.
mode: subagent
permission:
  "*": deny
  bash:
    "*": deny
    "pwd": allow
  skill:
    "*": deny
    "kos-contract-probe": allow
  task: deny
---

KOS_CONTRACT_CHILD

Load the contract skill, observe the working directory, and return exactly one requested JSON document without prose.
