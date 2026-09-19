# KOS

KOS is a small task state and coordination service for AI agents. This
repository currently contains the minimal Rails API foundation, the five core
domain tables and models, workflow validation, task graph invariants, and an
empty command-line interface. Domain operations will be added in later changes.
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
