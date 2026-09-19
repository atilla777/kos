# KOS

KOS is a small task state and coordination service for AI agents. This
repository contains the Rails state service, its authenticated JSON API, the
five core domain tables and models, workflow validation, task graph invariants,
atomic task lifecycle operations, and an empty command-line interface.
Persisted tasks retain their project and workflow and are cancelled rather than
physically deleted.

## Prerequisites

- Ruby 3.4.10
- Bundler 4.0.20
- SQLite 3 and its development headers

Install Bundler if it is not already available:

```sh
gem install bundler --version 4.0.20
```

Set a non-empty API bearer token before running KOS outside the test
environment:

```sh
export KOS_API_TOKEN="$(openssl rand -hex 32)"
```

Keep this value secret. Future application endpoints inherit bearer-token
authentication from `ApplicationController`; send the token as
`Authorization: Bearer <token>`. The readiness endpoint `GET /up` remains
public.

By default, development and production SQLite files live under
`$XDG_DATA_HOME/kos`, or `~/.local/share/kos` when `XDG_DATA_HOME` is unset.
Set `KOS_DATA_HOME` to override that directory. It must be on a local disk, not
in a synchronized or network-mounted directory. `KOS_DATA_HOME` must be an
absolute path outside the checkout; relative `XDG_DATA_HOME` values are ignored
as required by the XDG specification. Tests always use `tmp/test.sqlite3` and
ignore these data-directory variables.

Task ownership leases last six hours by default. Set `KOS_LEASE_SECONDS` to a
positive integer to use another duration.

## Setup

From a fresh checkout, install dependencies and prepare the local database:

```sh
bin/setup --skip-server
```

Prepare the empty test database explicitly:

```sh
RAILS_ENV=test bin/rails db:prepare
```

## Run

Start the API server:

```sh
bin/rails server
```

The readiness endpoint is available at `http://127.0.0.1:3000/up`.

## API

All application endpoints accept JSON and require the configured bearer token.
`GET /up` is the only public endpoint.

```text
POST  /projects
POST  /workflows
POST  /task_types
PATCH /task_types/:id
POST  /tasks
GET   /tasks/:id
PATCH /tasks/:id
POST  /tasks/claim-next
POST  /tasks/:id/resume
POST  /tasks/:id/report-attempt
POST  /tasks/:id/cancel
```

Request fields are top-level JSON properties. Task responses contain `task`,
`workflow`, and `step` objects so an agent receives the stored state and the
current instruction in one response. `claim-next` returns `204 No Content` when
no task is available. Known failures use a stable `error` code with status
`400`, `404`, `409`, or `422` as appropriate.

For example:

```sh
curl --request POST http://127.0.0.1:3000/projects \
  --header "Authorization: Bearer $KOS_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"name":"KOS","remote_url":"https://example.test/kos.git","default_branch":"main"}'
```

Display the CLI help:

```sh
bin/kos --help
```

## Verify

Run the complete non-mutating verification suite:

```sh
bin/check
```

The underlying commands can also be run separately:

```sh
bin/format  # Apply automatic formatting fixes
bin/lint    # Check formatting and style
bin/test    # Run the test suite
```

## Documentation

- [Product specification](docs/specification.md)
- [Architecture rules](docs/architecture.md)
- [Testing rules](docs/testing.md)
- [Contribution rules](CONTRIBUTING.md)

Production deployment is intentionally outside the current project scope.
