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

Domain behavior belongs in `docs/specs/`. There are no domain specifications yet. Add one when an implemented behavior needs a durable, user- or domain-observable contract.
