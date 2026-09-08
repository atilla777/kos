---
title: KOS Engineering Rules
status: active
---

# KOS Engineering Rules

These documents are normative for code and agent work in this repository. A more specific approved specification or ADR may refine a rule, but must not silently weaken a system invariant.

| Document | Scope |
| --- | --- |
| [Collaboration](collaboration.md) | Task scope, user decisions, implementation approval, and project planning |
| [Architecture](architecture.md) | Domain boundaries, state, CLI, persistence, and Git side effects |
| [Code Style](code-style.md) | Ruby and Rails implementation conventions |
| [Testing](testing.md) | Automated verification and quality gates |

Domain behavior belongs in the [domain specifications](../specs/index.md). Add or update a focused specification when behavior needs a durable user-, domain-, or integration-observable contract.
