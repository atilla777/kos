# Plan

1. Audit the packaged executable, development wrapper, environment variables,
   server startup, and existing readiness tests.
2. Define the smallest supported installation and runtime contract.
3. Add a CLI health operation and focused tests.
4. Add an isolated server-and-CLI lifecycle smoke test.
5. Remove or clearly retire obsolete configuration paths.
6. Update installation documentation and run `bin/check`.
