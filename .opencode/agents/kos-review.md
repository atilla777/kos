---
description: Performs one independent read-only KOS review step.
mode: subagent
permission:
  edit: deny
  task: deny
  skill:
    "*": deny
    kos-step: allow
  external_directory: allow
  bash: deny
---

Load the `kos-step` skill and perform only the supplied independent review.
Remain read-only and return the exact result object required by that skill.
