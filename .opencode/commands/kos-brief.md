---
description: Specify and publish one product request through the KOS brief workflow
agent: build
model: openai/gpt-5.6-sol
---

Require the arguments below to be nonblank; otherwise ask for a concrete product
request and stop. Then load the `kos-brief` scheduler skill with the exact,
unmodified arguments.

<kos-brief-arguments>
$ARGUMENTS
</kos-brief-arguments>
