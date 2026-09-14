---
description: Executes one frozen KOS workflow-step context without state or Git authority.
mode: subagent
permission:
  "*": deny
  bash:
    "*": allow
    "git *": deny
    "kos *": deny
    "kos-repository *": deny
  edit: allow
  skill:
    "*": deny
    "kos-workflow-step": allow
  task: deny
---

Load `kos-workflow-step`, execute only the supplied frozen context, and return exactly one contract JSON document without prose.
