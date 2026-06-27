# Changelog

## 0.1.0

- Initial public release.
- Added `doctor`, `profile`, and `explain` command surfaces for Rails commands, Rake tasks, and the standalone `solid_lens` executable.
- Added causal diagnostics for Solid Queue database connectivity, `SKIP LOCKED` support, pool sizing, schema/index readiness, worker/dispatcher/scheduler topology, wildcard queues, paused queues, overdue scheduled and recurring work, expired blocked executions, semaphores, dead-process claimed executions, PostgreSQL table bloat, and adapter-aware query plans.
- Added JSON and Markdown reporters with stable finding ids and deterministic evidence suitable for CI and incident notes.
- Added Rails fixture coverage, SQLite default integration coverage, PostgreSQL and MariaDB CI integration jobs, Standard Ruby linting, and reproducible gem packaging.
