# Live Acceptance Evidence

Date: 2026-09-25

## Environment

- OpenCode 1.18.26 with the integration and CLI gem installed from commit
  `fb1aa7c` into isolated configuration and gem homes.
- Rails used an isolated SQLite database and KOS data home.
- The fixture used canonical origin
  `git@kos-live.invalid:acceptance/greeting.git`; an isolated SSH transport
  mapped it to a local bare remote without bypassing repository identity checks.
- OpenCode provider credentials were inherited, but no credentials, tokens, raw
  transcripts, or server logs are stored in this evidence bundle.
- Raw JSON event streams were retained only in the temporary acceptance area and
  counted by `"tool":"task"` events.

## Results

| Command | Task | Elapsed | Step agent launches | Result |
| --- | ---: | ---: | ---: | --- |
| `/kos-brief` initial | 1 | 184.18 s | 1 | Paused at `brief` with one precise product question. |
| brief resume | 1 | 580.09 s | 4 | Completed after `brief`, `review`, `publish`, and `verify`. |
| `/kos` | 2 | 821.64 s | 6 | Completed all six development steps. |
| `/kos-fix` | 3 | 790.13 s | 7 | Completed all seven fix steps. |
| identical `/kos-brief` repeat | 1 | 59.29 s | 0 | Returned the existing completed task. |
| identical `/kos-fix` repeat | 3 | 55.65 s | 0 | Returned the existing completed task. |

The three representative scenarios took 2,376.04 seconds (39 minutes 36
seconds) of model execution in total, excluding setup and the terminal repeats.
They launched 18 fresh focused agents. One manual intervention answered the
brief question: `--shout` is accepted before or after the optional name.

## Server Evidence

- Task 1 is `completed` at `verify`, has no owner or lease, and has accepted
  `brief`, `review`, `publish`, and `verify` artifacts.
- Task 1 materialized exactly child task 2 with no sibling blockers. The child
  initially depended on task 1 and became claimable after task 1 completed.
- Task 2 is `completed` at `verify`, has no owner or lease, and has all six
  development artifacts.
- Task 3 is `completed` at `verify`, has no owner or lease, and has all seven fix
  artifacts.
- Byte-identical request repeats returned tasks 1 and 3 and launched no focused
  agents, proving no duplicate request-bound task was created.

The exact public context and child projections are stored in
`task-1-context.json`, `task-1-children.json`, `task-2-context.json`, and
`task-3-context.json`.

## Remote Evidence

Independent observation of the bare remote found one task publication commit
for each scenario:

- `c1733b810fdf08080dac9957831a2909f9fd8a28` for task 1;
- `acffeb96437d59732ff1d854be509827327f6122` for task 2; and
- `514665b6664037b4bdefcc47ad45b8ac3a4e1786` for task 3.

Each commit has one matching `KOS-Task` trailer. Terminal request repeats did
not add commits. `remote-history.txt` and `remote-commits.txt` preserve the
independently observed history and commit statistics.

After fetching and resetting an independent observer clone to remote `main`, the
fixture checks passed:

```text
ruby test/greeting_test.rb: 3 runs, 12 assertions, 0 failures, 0 errors
ruby test/farewell_test.rb: 1 run, 1 assertion, 0 failures, 0 errors
```

## Failures And Interventions

- The first timing wrapper used unavailable `/usr/bin/time`; no scenario was
  started. Subsequent timings used nanosecond wall-clock timestamps.
- The initial brief correctly paused rather than choosing an unspecified flag
  position. One answer resumed the same OpenCode session and persisted task.
- During task 2, the acceptance environment set `GEM_PATH` to only the isolated
  CLI gem home, hiding the system `minitest`. Implementation recorded that the
  required test could not run, but documentation, review, publication, and
  verification still accepted and completed the task. Independent execution
  with the normal Ruby paths later passed the test, so the published result was
  valid, but the workflow incorrectly allowed publication without a successful
  required check in accepted implementation evidence.
- Task 3 used both isolated and system gem paths. Its implementation artifact
  records both documented test commands passing before review and publication.

The check-evidence gap is actionable and is tracked separately as task 010. No
workflow or data-model redesign was implemented during this acceptance task.
