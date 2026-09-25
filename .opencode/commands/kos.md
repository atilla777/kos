---
description: Resume or run the next KOS development task through its workflow
agent: build
model: openai/gpt-5.6-terra
---

Require the arguments below to be blank; otherwise explain that `/kos` only runs
existing development tasks and stop. Then load the `kos` scheduler skill in
`development` mode.

<kos-arguments>
$ARGUMENTS
</kos-arguments>
