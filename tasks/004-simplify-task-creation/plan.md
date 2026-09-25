# Plan

1. Reduce the required guarantees to server idempotency and observable response
   semantics.
2. Adjust the API and CLI only where the current create-and-claim contract is
   insufficient for a safe identical retry.
3. Replace local-protocol tests with server and CLI retry tests.
4. Remove obsolete creation-state documentation and skill instructions.
5. Verify compatibility with persisted keyed tasks and run `bin/check`.
