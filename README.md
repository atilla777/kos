# KOS

KOS is a small task state and coordination service for AI agents. This
repository currently contains the minimal Rails API foundation and an empty
command-line interface. Domain operations will be added in later changes.

## Prerequisites

- Ruby 3.4.10
- Bundler 4.0.20
- SQLite 3 and its development headers

Install Bundler if it is not already available:

```sh
gem install bundler --version 4.0.20
```

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
