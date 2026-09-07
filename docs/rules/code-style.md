---
title: KOS Ruby and Rails Style Rules
status: active
---

# KOS Ruby and Rails Style Rules

## Ruby

- Target the Ruby version declared by the project and use standard Ruby and Rails idioms before adding dependencies.
- Use clear, domain-oriented names. Avoid abbreviations, boolean flags that select unrelated behavior, and generic names such as `Manager`, `Helper`, or `Utils`.
- Keep methods focused and objects cohesive. Extract a named object when it represents a stable domain concept or isolates a boundary.
- Prefer immutable values and explicit return values at domain and integration boundaries. Do not mutate arguments unexpectedly.
- Raise or return explicit, domain-specific failures. Do not rescue broad exceptions, swallow errors, or use exceptions for normal control flow.
- Validate untrusted input at the CLI or adapter boundary. Domain objects may assume their typed inputs satisfy that boundary contract.

## Rails

- Follow Rails conventions for file layout, naming, migrations, validations, and associations.
- Use Active Record validations for useful feedback, and database constraints for invariants.
- Avoid business logic in callbacks. Use callbacks only for local model lifecycle housekeeping that cannot fail independently or invoke side effects.
- Avoid N+1 queries. Load associations deliberately and add a query-level test when an operation depends on a non-trivial query shape.
- Make migrations explicit, safe for existing data, and free of application-model assumptions that may change later.
- Keep configuration in Rails configuration and environment variables, never in hard-coded machine-specific paths or secrets.

## Quality Gate

- Run `bundle exec rubocop` for every Ruby change when the project toolchain is available.
- Configure RuboCop in the repository. Do not disable a cop inline or globally without a concise justification and a narrowly scoped configuration change.
- Format and lint documentation, YAML, and shell files with the project-provided tools when they are introduced.
