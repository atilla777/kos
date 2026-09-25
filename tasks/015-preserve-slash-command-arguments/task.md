# Preserve Exact Slash-Command Arguments

## Goal

Ensure request-bound slash commands preserve the user's exact argument bytes
across independent OpenCode runs.

## Scope

- Reproduce the live observation where a runner invoked `/kos-brief` with a
  visually unquoted request but `$ARGUMENTS` reached `task create-or-get` as the
  same UTF-8 bytes surrounded by literal `0x22` characters.
- Identify whether command expansion, scheduler interpretation, or request input
  introduces or removes quote bytes.
- Make repeated `/kos-brief` and `/kos-fix` requests produce identical server
  request bytes and creation keys.
- Add deterministic regression coverage for exact argument preservation.

## Acceptance Criteria

- Independent runs of the same slash command submit byte-identical requests.
- Quotes explicitly typed inside the slash-command payload remain data.
  Syntactic quotes used by a caller or runner only to delimit the command
  argument are not included in the request bytes.
- Regression tests compare the exact expected and submitted byte strings and
  their derived creation keys at the command-to-scheduler and scheduler-to-CLI
  boundaries.
- Exact request repeats return the existing task without focused-agent launches.
- `bin/check` passes.
