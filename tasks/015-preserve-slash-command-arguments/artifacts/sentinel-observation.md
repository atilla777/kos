# Slash-Command Sentinel Observation

Date: 2026-09-25
OpenCode: 1.18.26

This is external live evidence, not automated repository coverage of OpenCode
internals. The exact isolated command file is `argument-sentinel.md`; its
SHA-256 is
`d2fef602583739d3b99b1169feb965cf28c8cc7b229287353dbc365bcfb7a169`.

Eight independent sessions were executed from the repository root while that
exact file was temporarily registered as a project command. The registration
was removed after observation. The exact shell commands were run twice each:

```sh
opencode run --format json --command argument-sentinel "ORDINARY MULTIWORD 015"
opencode run --format json --command argument-sentinel ORDINARY MULTIWORD 015
opencode run --format json --command argument-sentinel 'display literal "ready" 015'
opencode run --format json --command argument-sentinel $'\n BOUNDARY_WHITESPACE_015 \n'
```

The shell passed the first and third requests as one argv each. OpenCode
display-serialized those argv before `$ARGUMENTS` expansion: it added wrapper
`0x22` bytes and, in the third case, added `0x5c` before each literal `0x22`.
The second command passed three separate argv words; its expansion was the exact
plain words joined by spaces, with no wrapper bytes. The fourth command confirms
the same wrapper behavior around one argv containing boundary newlines.

The exact argv and the bytes between the expanded `<argument-sentinel>` tags in
each exported user prompt were projected into `sentinel-runs.json`. That file
retains sanitized argv text and hex, expanded hex, byte length, and SHA-256 for
every run. It contains no session ID, transcript, credential, or filesystem/home
path. `verify_sentinel_evidence.rb` verifies the retained command bytes, exact
argv, exact expansions, their distinct relationships, all eight projections and
digests, and byte equality within all four independent-run pairs.

| Invocation | Message argv | Expanded bytes | Pair result |
| --- | --- | --- | --- |
| One quoted multiword argv | `ORDINARY MULTIWORD 015` | `"ORDINARY MULTIWORD 015"` (24 bytes) | byte-identical |
| Three separate argv words | `ORDINARY`, `MULTIWORD`, `015` | `ORDINARY MULTIWORD 015` (22 bytes) | byte-identical |
| One quoted argv with literal quotes | `display literal "ready" 015` | `"display literal \"ready\" 015"` (31 bytes) | byte-identical |
| One boundary-whitespace argv | newline-delimited value | wrapper quotes plus exact value (29 bytes) | byte-identical |

This establishes an OpenCode 1.18.26 CLI limitation, not a KOS normalization
rule. KOS treats the expansion as authoritative and intentionally does not infer
argv, remove wrappers, or unescape. Interactive slash-command payloads and
separate `opencode run --command ...` argv words are the supported exact paths.
Deterministic repository tests separately cover post-expansion command framing,
the scheduler-to-fake-CLI stdin handoff, packaged CLI transport, and server
persistence, hashing, and idempotence.
