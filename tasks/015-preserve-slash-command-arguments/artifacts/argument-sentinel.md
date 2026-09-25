---
description: Capture deterministic command argument expansion
agent: build
model: openai/gpt-5.6-terra
---

Return only `captured` and do not use tools.

<argument-sentinel>
$ARGUMENTS
</argument-sentinel>
