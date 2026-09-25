# Preserve Exact Slash-Command Arguments

## Goal

Ensure request-bound slash commands preserve the exact OpenCode `$ARGUMENTS`
expansion bytes across independent runs.

## Scope

- Reproduce the live observation where a runner invoked `/kos-brief` with a
  visually unquoted request but `$ARGUMENTS` reached `task create-or-get` as the
  same UTF-8 bytes surrounded by literal `0x22` characters.
- Identify whether command expansion, scheduler interpretation, or request input
  introduces or removes quote bytes.
- Record the accepted OpenCode 1.18.26 limitation: one argv containing spaces is
  display-serialized with wrapper quotes and escaped literal quotes, while
  interactive payloads and separate CLI argv words are supported exact paths.
- Make repeated `/kos-brief` and `/kos-fix` requests produce identical server
  request bytes and creation keys.
- Add deterministic regression coverage for exact argument preservation.

## Acceptance Criteria

- Independent runs of the same invocation produce byte-identical expansions.
- KOS preserves every expansion byte and does not guess or reverse OpenCode's
  wrapper quoting or backslash escaping.
- Regression tests compare exact post-expansion and submitted byte strings and
  their derived creation keys at the command-to-scheduler, scheduler-to-CLI,
  packaged CLI, and server boundaries.
- Exact request repeats return the existing task without focused-agent launches.
- `bin/check` passes.
