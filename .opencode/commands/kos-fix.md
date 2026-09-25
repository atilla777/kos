---
description: Diagnose and fix one reported problem through the KOS fix workflow
agent: build
model: openai/gpt-5.6-terra
---

Require the arguments below to be nonblank; otherwise ask for a concrete problem
description and stop. Then load the `kos` scheduler skill in `fix` mode with the
exact, unmodified arguments.

<kos-fix-arguments>
$ARGUMENTS
</kos-fix-arguments>
