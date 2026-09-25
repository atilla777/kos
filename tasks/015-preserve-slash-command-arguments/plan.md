# Plan

1. Reproduce argv and expansion bytes for quoted and separate multiword CLI
   invocation, literal quotes, and a boundary-whitespace case.
2. Document the OpenCode 1.18.26 serializer limitation and KOS's exact
   post-expansion preservation boundary without adding an unquoting heuristic.
3. Add deterministic framing, fake-CLI, packaged-CLI, persistence, creation-key,
   and idempotence regression coverage.
4. Run the evidence verifier, focused checks, and `bin/check`.
