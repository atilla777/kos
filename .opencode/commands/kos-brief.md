---
description: Specify and publish one product request through the KOS brief workflow
agent: build
model: openai/gpt-5.6-sol
---

Require the argument expansion below to be nonblank; otherwise ask for a concrete product
request and stop. Request data is exactly that expansion; preserve every byte inside it, including quotes, backslashes, and leading or trailing whitespace/newlines. Never infer or unescape the originating argv. The tags and exactly one framing newline before and after the expansion are not request data. Then load the `kos` scheduler skill in `brief` mode.

<kos-brief-arguments>
$ARGUMENTS
</kos-brief-arguments>
