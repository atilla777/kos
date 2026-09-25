# Plan

1. Reproduce the expected unquoted bytes and observed `0x22`-wrapped bytes at
   each slash-command expansion boundary.
2. Implement the smallest preservation fix at the responsible boundary.
3. Add deterministic byte-string and creation-key regression coverage.
4. Run focused checks and `bin/check`.
