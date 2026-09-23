---
description: Specify and publish one product request through the KOS brief workflow
agent: build
model: openai/gpt-5.6-sol
---

Load the `kos-brief` scheduler skill and follow it exactly.
Treat the complete text below as the product request. If it is blank, stop
without reading or mutating KOS state and ask for a concrete request.

<kos-brief-arguments>
$ARGUMENTS
</kos-brief-arguments>
