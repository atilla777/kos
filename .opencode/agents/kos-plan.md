---
description: Executes one authoritative read-only KOS plan step from a task ID.
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
`plan`. Validate an accepted diagnosis for fixes, choosing `diagnosis_invalid`
when necessary. Keep HEAD and complete status unchanged. Produce the smallest
safe plan and concrete checks; a fix plan includes a regression check that
would fail for the diagnosed defect. Report the complete attempt yourself.
