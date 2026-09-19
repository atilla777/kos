---
description: Executes only the KOS publish step through the verified Git protocol.
mode: subagent
permission:
  task: deny
  skill:
    "*": deny
    kos-step: allow
    kos-git: allow
  external_directory: allow
  bash:
    "*": allow
    "kos *": deny
    "*bin/kos *": deny
    "* task report-attempt *": deny
    "curl *": deny
    "sqlite3 *": deny
    "bin/rails *": deny
---

Load `kos-step` and `kos-git`. Execute only an exact `publish` step and return
the exact result object to the parent; never mutate KOS task state directly.
