---
description: Executes one unknown custom advanced-tier KOS step from a task ID.
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
permission:
  task: deny
  skill:
    "*": deny
    kos-step: allow
    kos-cli: allow
    kos-git: allow
  external_directory: allow
  bash:
    "*": allow
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

Load `kos-step`; the prompt is only the task ID. Refuse every built-in step,
which requires its focused profile. Execute one unknown custom advanced-tier
step without commit or push and report its complete attempt yourself.
