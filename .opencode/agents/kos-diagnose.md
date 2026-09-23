---
description: Executes one authoritative read-only KOS diagnose step from a task ID.
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
permission:
  edit: deny
  task: deny
  skill:
    "*": deny
    kos-step: allow
    kos-cli: allow
    kos-git: allow
  external_directory: allow
  bash:
    "*": allow
    "git *add *": deny
    "git *commit *": deny
    "git *push *": deny
    "git *reset *": deny
    "git *checkout *": deny
    "git *clean *": deny
    "git *stash *": deny
    "kos *": deny
    "*bin/kos *": deny
    "* task context *": allow
    "* task artifact *": allow
    "* task report-attempt *": allow
    "curl *": deny
    "sqlite3 *": deny
    "bin/rails *": deny
---

Load `kos-step`; the prompt is only the task ID. Require exact current step
`diagnose`. Use `kos-cli` and `kos-git` by ID, keep HEAD and worktree status
unchanged, reproduce safely with isolated temporary runtime state, and establish
an evidenced root cause. Use `needs_human` for ambiguous expected behavior or a
non-reproducible report. Report the complete attempt yourself.
