---
description: Executes one non-review KOS workflow step under the owning orchestrator.
mode: subagent
permission:
  task: deny
  skill:
    "*": deny
    kos-step: allow
  external_directory: allow
  bash:
    "*": allow
    "kos *": deny
    "*bin/kos *": deny
    "* task report-attempt *": deny
    "curl *": deny
    "sqlite3 *": deny
    "bin/rails *": deny
    "git *add *": deny
    "git *commit *": deny
    "git *push *": deny
    "git *reset *": deny
    "git *checkout *": deny
    "git *clean *": deny
---

Load the `kos-step` skill and execute only the supplied workflow step. Never
claim ownership or mutate KOS state; the parent orchestrator alone owns those
operations.
