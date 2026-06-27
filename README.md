# SolidLens

SolidLens is a causal diagnostic toolkit for Solid Queue. It is intentionally not a dashboard. The first goal is to explain production failure modes around database-backed job processing: pool pressure, lock support, polling shape, dispatcher lag, claimed jobs, table bloat, and critical query plans.

The current product boundary is locked in [docs/specs/product-direction.md](docs/specs/product-direction.md), and the repo has an executable product-spec test to guard that surface against drift.

## Problem

Solid Queue removes Redis from many Rails job deployments, but it moves the operational risk into the queue database. When jobs stall, the useful question is rarely "is the dashboard red?" It is "which database-backed failure mode is causing this, and what evidence proves it?"

SolidLens exists for that incident/debugging moment. It inspects the Rails runtime, Solid Queue topology, queue database, schema, indexes, backlog tables, recurring schedule state, concurrency semaphores, process heartbeats, PostgreSQL bloat, and critical query plans, then emits findings with stable ids and recommendations that can be used in CI or an incident note.

## Why This Exists

Most teams can already graph queue depth. Fewer can quickly explain whether a Solid Queue deployment is unhealthy because the queue DB pool is undersized, `SKIP LOCKED` is missing, wildcard queues are forcing expensive discovery, dispatchers cannot release scheduled jobs, recurring tasks have no usable scheduler, concurrency semaphores are leaking, claimed jobs belong to dead processes, or PostgreSQL dead tuples are distorting plans.

SolidLens keeps that scope narrow on purpose: no UI, no daemon, no generic Active Job monitor, and no vanity metrics without an operator action.

## Use Cases

- Run `doctor` in CI or pre-production to catch broken queue DB connectivity, missing Solid Queue schema/indexes, pool pressure, invalid topology, and unsupported lock behavior before deploy.
- Run `profile` during an incident window to prove whether ready, scheduled, recurring, blocked, semaphore, claimed-execution, or bloat pressure is growing or only spiking transiently.
- Run `explain` when queue polling or dispatch latency looks database-bound and you need adapter-aware query-plan evidence for SQLite, PostgreSQL, MySQL, or MariaDB.

## Commands

Inside a Rails app using Solid Queue, these Rails commands are the primary production path:

```sh
bin/rails solid_lens:doctor
bin/rails solid_lens:profile --duration=60
bin/rails solid_lens:explain
```

The executable can also bootstrap Rails automatically when it detects a Rails app or when `--app-root` is provided:

```sh
bundle exec solid_lens doctor --format=json --output=tmp/solid_lens.json --fail-on-high
bundle exec solid_lens profile --duration=60
bundle exec solid_lens profile --duration=60 --sample-interval=5
bundle exec solid_lens explain --format=markdown
bundle exec solid_lens doctor --app-root=/path/to/app --rails-env=production --fail-on-high
```

The CLI now tries to boot Rails before collecting evidence. It will:

- auto-detect a Rails app by walking up from the current directory;
- honor `--app-root=PATH` when diagnostics should run from outside the app root;
- honor `--rails-env=ENV` to set `RAILS_ENV` and `RACK_ENV` before boot.

`bin/rails solid_lens:*` remains the most explicit path for app-local usage, but the standalone CLI is now viable for CI wrappers and operational tooling.

The gem still keeps the Rake-task path available, including `DURATION=60` / `SAMPLE_INTERVAL=5` via environment variables, but the Rails command surface now accepts long options directly.

The standalone CLI remains the canonical execution path internally. Both the Rails command and the compatibility Rake tasks now funnel into that path, which keeps `--output`, `fail-on-high`, and format validation aligned across entrypoints.

Both the standalone CLI and the Rails entrypoints now create parent directories for `--output`/`OUTPUT` automatically and reject unknown output formats with a usage-style exit code instead of silently falling back.

Markdown reports now include the full collected evidence as a JSON block before the findings section, so human incident/debugging workflows can inspect the same runtime, database, queue-config, and table evidence that CI consumes from JSON output.

`profile` is now more than a start/end row count diff. It summarizes:

- per-table delta and rate per second across the profile window;
- periodic samples across the profile window, controlled by `--sample-interval` or `SAMPLE_INTERVAL`;
- automatic sample-interval coarsening when the requested interval would otherwise explode timeline cardinality for long windows;
- ready backlog growth, oldest ready age growth, and queue-specific backlog deltas;
- ready backlog peaks, queue peak depth, and spikes that may recover before the final sample;
- scheduled backlog growth and oldest overdue scheduled lag growth;
- scheduled backlog and lag peaks, so transient dispatch stalls are still visible;
- overdue recurring task growth and oldest recurring lag growth;
- recurring-task lag peaks, so transient scheduler stalls are still visible too;
- blocked backlog growth, expired blocked growth, queue-specific blocked peaks, and oldest expired blocked lag growth;
- expired semaphore accumulation and semaphore-cleanup lag growth during the profile window;
- expired orphan semaphore growth and orphan-cleanup lag growth during the profile window;
- claimed executions stranded by dead processes, including oldest dead-claim lag growth during the profile window;
- PostgreSQL dead-tuple growth and peak bloat per Solid Queue table during the profile window;
- profile-specific findings when backlog, dispatch lag, or table bloat grows during the observed window.

The profile evidence also records `requested_sample_interval_seconds`, the effective `sample_interval_seconds`, `sample_limit_applied`, and `max_samples`, so operators can see when long windows were intentionally coarsened to keep reports bounded. Sampling now targets scheduled offsets across the whole profile window and still captures a final end-of-window sample, so short intervals stay reliable even when evidence collection itself has some overhead.

## Current Checks

- database version versus `FOR UPDATE SKIP LOCKED` support;
- worker threads, worker processes, polling intervals, dispatcher polling behavior, and scheduler polling behavior;
- queue configuration file syntax/ERB errors and runtime-configuration inspection failures that would degrade topology diagnostics;
- expired blocked jobs versus dispatcher concurrency maintenance coverage and interval;
- expired concurrency semaphores versus dispatcher maintenance coverage and interval;
- expired concurrency semaphores that no longer have matching blocked backlog;
- queue database connection pool size;
- queue database connectivity and queue DB selection;
- Solid Queue schema completeness;
- presence of critical poll, dispatch, blocked-recovery, semaphore-cleanup, and process-heartbeat indexes;
- wildcard queue specs;
- paused queues;
- overdue scheduled jobs;
- overdue recurring tasks based on recurring schedule versus recorded executions;
- overdue recurring tasks with no scheduler configured in the local Solid Queue topology;
- jobs claimed by missing or stale processes;
- PostgreSQL dead-tuple bloat on Solid Queue tables;
- `EXPLAIN` for critical polling, dispatch, and blocked-job release queries when blocked backlog exists;
- JSON and Markdown report output for CI.

Configuration diagnostics now also flag:

- workers with invalid `threads`, `processes`, or `polling_interval` values;
- dispatchers with invalid `polling_interval`, `batch_size`, or `concurrency_maintenance_interval` settings;
- schedulers with invalid `polling_interval` settings;
- dynamic recurring tasks that exist in the queue database but are ignored because scheduler `dynamic_tasks_enabled` is disabled;
- overdue scheduled jobs that only have invalid dispatchers configured;
- overdue recurring tasks that only have missing or unusable scheduler coverage;
- `processes` settings that look real in `queue.yml` but are ignored because Solid Queue is running in `async` mode;
- dispatchers whose polling interval is so high that scheduled-job release latency becomes operator-visible.
- schedulers whose polling interval is so high that recurring-task release latency becomes operator-visible.
- blocked executions that have already expired but still outlive the dispatcher concurrency-maintenance interval.
- concurrency semaphores that have already expired but still outlive the dispatcher concurrency-maintenance interval.
- expired concurrency semaphores whose keys no longer have matching blocked executions, which usually indicates leaked semaphore rows rather than just slow backlog recovery.

Blocked/semaphore maintenance findings now only trust dispatchers with a real maintenance path: `concurrency_maintenance` enabled, positive `polling_interval`, and positive `concurrency_maintenance_interval`.

Scheduled-job and recurring-task findings now also treat unusable topology as absent: overdue scheduled jobs require at least one dispatcher with positive polling and batch settings, and overdue recurring tasks require a scheduler with positive polling plus dynamic task loading when dynamic recurring tasks exist.

Profile diagnostics now also flag:

- ready execution backlog that grows during the profile window;
- ready execution backlog that spikes during the profile window even if the final snapshot recovers;
- scheduled backlog or dispatch lag that grows during the profile window;
- recurring-task delivery lag that grows during the profile window;
- blocked backlog or expired blocked lag that grows during the profile window;
- expired semaphore backlog that grows during the profile window;
- expired orphan semaphores that grow during the profile window;
- dead-process claimed executions that accumulate during the profile window;
- PostgreSQL dead-tuple bloat that grows or spikes during the profile window.

Pool sizing follows the Solid Queue guidance directly: each worker thread consumes one queue DB connection, and two more connections are reserved for polling and heartbeat. SolidLens reports the required pool size from the effective worker configuration instead of guessing from raw YAML alone.

Queue-topology evidence now resolves effective worker, dispatcher, and scheduler defaults before checks run, and the same normalized shape is preserved in `configured_processes`, so reports show actual threads, processes, polling intervals, batch size, concurrency-maintenance settings, and scheduler polling behavior even when `queue.yml` only specifies a partial override.

`explain` is now adapter-aware:

- SQLite uses `EXPLAIN QUERY PLAN` so the report contains usable `detail` rows instead of low-level bytecode;
- PostgreSQL uses `EXPLAIN (FORMAT JSON)` and now has end-to-end integration coverage against a real server;
- MySQL, MariaDB, and compatible adapters keep tabular `EXPLAIN` rows, and MariaDB now has real integration coverage through the Trilogy adapter;
- wildcard queue configurations also explain the queue-discovery query, because that lookup can become the bottleneck before polling itself does.

## Architecture

The internal contract is:

```ruby
Finding.new(
  id: "solid_queue.pool.undersized",
  severity: :high,
  title: "Queue database pool is undersized",
  evidence: {
    worker_threads: 10,
    queue_db_pool: 10,
    reserved_connections: 2,
    safe_worker_threads: 8
  },
  recommendation: "Increase the queue DB pool to >= 12 or reduce worker threads to <= 8."
)
```

The implementation follows:

- `SolidLens::Collectors`: gather runtime, config, database, and table evidence;
- `SolidLens::Checks`: convert evidence into findings;
- `SolidLens::Reporters`: render Markdown or JSON for humans and CI;
- `SolidLens::Runner`: orchestrates command-specific collection and checks.

## Verification

For a reviewer evaluating this repository locally:

```sh
bundle install
bundle exec rake
bundle exec ruby -Itest test/solid_lens/command_surface_integration_test.rb
bundle exec ruby -Itest test/solid_lens/postgres_integration_test.rb
bundle exec ruby -Itest test/solid_lens/mariadb_integration_test.rb
bundle exec rake build
gem contents pkg/solid_lens-0.1.0.gem
```

The default `bundle exec rake` gate runs the SQLite-backed test suite and Standard Ruby. PostgreSQL and MariaDB integration tests need either their CI service containers or local databases exposed through `SOLID_LENS_TEST_DATABASE_URL` and `SOLID_LENS_TEST_MARIADB_DATABASE_URL`.

- unit and integration tests run against the real `solid_queue` 1.4.0 schema;
- a minimal Rails app fixture boots the Railtie and exercises the exact `bin/rails solid_lens:doctor|profile|explain` command surface;
- the integration suite asserts runtime `queue.yml` interpretation, pool findings, stale claimed execution detection, Rails command and Rake task report output, missing-index/schema findings, and CLI Rails auto-bootstrap.
- PostgreSQL integration coverage boots the fixture app against a real database, reloads the Solid Queue schema, verifies `SKIP LOCKED` support evidence, asserts JSON `EXPLAIN` output, and confirms `profile` emits structured bloat-health evidence from the standalone CLI.
- MariaDB integration coverage boots the same fixture app against a real database through Trilogy, verifies the MariaDB `SKIP LOCKED` version branch, and asserts MySQL-style `EXPLAIN` output from the standalone CLI.
- runtime configuration coverage now also verifies that `async` mode correctly surfaces ignored worker `processes` settings as an actionable finding.
- profile coverage now verifies real ready/scheduled/recurring backlog growth, recovered spikes, blocked backlog growth, expired semaphore growth, dead claimed execution growth, synthetic bloat spikes in the collector/check pipeline, bounded sample-cardinality behavior, queue peaks, overdue scheduled lag growth, recurring lag growth, and CLI JSON output for the `profile` command.
- blocked-execution coverage now verifies real expired blocked backlog detection, blocked-job release query explain coverage, and timestamp lag calculations against database-returned timestamps.
- semaphore-health coverage now verifies real expired semaphore detection and the dispatcher-maintenance lag path against the real Solid Queue schema.
- explain-plan analysis also has unit coverage for SQLite, PostgreSQL-style JSON plans, and MySQL-style tabular plans.
- CI now includes dedicated PostgreSQL and MariaDB integration jobs in addition to the default SQLite-backed suite.

## Compatibility

SolidLens targets Ruby `>= 3.2`, Rails/Railties `>= 7.1, < 9.0`, and Solid Queue `>= 1.4, < 2.0`.

The Solid Queue README says new Rails 8 apps configure Solid Queue by default, and that high-throughput use benefits from MySQL 8+, MariaDB 10.6+, or PostgreSQL 9.5+ because those databases support `FOR UPDATE SKIP LOCKED`.

## Limits

- SolidLens reads queue state; it does not repair or mutate Solid Queue tables.
- It reports database and topology evidence from the environment where it runs. In multi-deployment systems, confirm which deployment owns scheduler and dispatcher work for the shared queue database.
- PostgreSQL bloat diagnostics use `pg_stat_user_tables`; non-PostgreSQL adapters still get schema, topology, backlog, explain, semaphore, and claimed-execution diagnostics but not dead-tuple evidence.
- `profile` is a bounded sampling window, not continuous monitoring. Use it to capture causal evidence, then hand sustained alerting to your metrics/APM stack.
