---
description: Diagnose and fix one reported problem through the KOS fix workflow
agent: build
model: openai/gpt-5.6-terra
---

Require the argument expansion below to be nonblank; otherwise ask for a concrete problem
description and stop. Request data is exactly that expansion; preserve every byte inside it, including quotes, backslashes, and leading or trailing whitespace/newlines. Never infer or unescape the originating argv. The tags and exactly one framing newline before and after the expansion are not request data. Then load the `kos` scheduler skill in `fix` mode.

<kos-fix-arguments>
$ARGUMENTS
</kos-fix-arguments>
