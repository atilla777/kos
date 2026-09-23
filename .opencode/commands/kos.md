---
description: Resume or run the next KOS development task through its workflow
agent: build
model: openai/gpt-5.6-terra
---

Load the `kos` scheduler skill and follow it exactly. This command accepts no arguments.
If the text below is nonblank, stop without reading or mutating KOS state and
explain that new work must already exist as a development task.

<kos-arguments>
$ARGUMENTS
</kos-arguments>
