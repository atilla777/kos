---
description: Executes the only commit-and-push KOS publish step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
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
    "kos *": deny
    "*bin/kos *": deny
    "* task context *": allow
    "* task artifact *": allow
    "* task children *": allow
    "* task validate-children *": allow
    "* task materialize-children *": allow
    "* task report-attempt *": allow
    "curl *": deny
    "sqlite3 *": deny
    "bin/rails *": deny
---

Load `kos-step`; the prompt is only the task ID. Require exact current step
`publish`. Validate accepted review evidence and use `review_invalid` when it is
not publishable. Load `kos-git`; this profile alone may update a moved base,
commit, and push. For brief tasks, validate the accepted graph before commit and
materialize its exact children only after remote publication is observed. Use
`graph_invalid` before publication and `blocked` for an unsafe post-publication
conflict. Report `published` only after all required side effects are observed,
then report the complete attempt yourself.
