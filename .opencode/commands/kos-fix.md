---
description: Diagnose and fix one reported problem through the KOS fix workflow
agent: build
model: openai/gpt-5.6-terra
---

Load the `kos` skill and follow its `/kos-fix` path exactly. Treat the complete
text below as the problem description. If it is blank, stop without reading or
mutating KOS state and ask for a concrete problem description.

<kos-fix-arguments>
$ARGUMENTS
</kos-fix-arguments>
