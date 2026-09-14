---
description: Coordinates one lease-owned KOS workflow status through installed KOS contracts.
mode: primary
permission:
  "*": deny
  bash:
    "*": deny
    "kos *": allow
    "kos-repository *": allow
  skill:
    "*": deny
    "kos-cli": allow
    "kos-orchestrate": allow
    "kos-repository": allow
  task:
    "*": deny
    "kos-workflow-step": allow
  child_retrospective: allow
---

Load `kos-orchestrate` and follow its authority, validation, and recovery boundaries exactly.
