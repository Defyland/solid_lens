# SolidLens Product Direction

## Goal

SolidLens exists to explain why a Solid Queue deployment is unhealthy in production. It is not a generic monitoring product and it is not a dashboard.

The gem should stay focused on causal diagnostics for database-backed job execution:

- queue database readiness and throughput risk;
- worker, dispatcher, and scheduler topology mistakes;
- query-plan, lock-support, and index problems;
- backlog, claim, semaphore, and bloat pathologies;
- CI-friendly reports that tell an operator what to change next.

## Operator

The primary user is a Rails operator debugging a production or pre-production Solid Queue deployment.

The gem is successful when that operator can run one command and get:

- evidence tied to the live runtime and queue database;
- findings with stable ids, severities, and recommendations;
- output that is deterministic enough for CI and incident playbooks.

## In Scope

The highest-priority diagnostic domains are:

1. Queue database compatibility and capacity:
   - adapter and version support for `SKIP LOCKED`;
   - queue database connectivity;
   - queue database pool sizing;
   - critical Solid Queue index readiness;
   - targeted PostgreSQL bloat evidence.
2. Queue process topology:
   - workers, threads, processes, polling intervals;
   - dispatchers and scheduled-job release health;
   - scheduler and recurring-task execution only when that affects causal delivery risk.
3. Live queue pathologies:
   - wildcard queue discovery cost;
   - paused queues;
   - overdue scheduled executions;
   - blocked executions and semaphore cleanup lag;
   - claimed jobs stranded by dead processes.
4. Deep-dive command paths:
   - `doctor` for current-state diagnosis;
   - `profile` for temporal growth and spikes;
   - `explain` for critical polling and dispatch query plans.

## Out Of Scope

SolidLens should not drift into:

- a web dashboard or admin UI;
- a generic Active Job monitor;
- Solid Cache or Solid Cable diagnostics in the MVP/early production path;
- vanity metrics without a concrete operator action;
- broad observability plumbing that duplicates APM or metrics systems.

## Public Surface Contract

The public command surface is intentionally small:

- `bin/rails solid_lens:doctor`
- `bin/rails solid_lens:profile`
- `bin/rails solid_lens:explain`
- `bundle exec solid_lens doctor|profile|explain`

Reports must remain available in:

- JSON for CI and machine consumption;
- Markdown for human incident/debugging workflows.

Exit behavior must stay conservative:

- zero by default;
- non-zero only when explicitly requested by `fail-on-high`.

## Evolution Bar

A new diagnostic belongs in SolidLens only if it passes all of these:

1. It explains a real Solid Queue failure mode or throughput risk.
2. It produces actionable evidence and a recommendation.
3. It fits the existing contract:
   `collector -> evidence -> check -> severity -> recommendation -> reporter`
4. It does not require adding a dashboard, background daemon, or product surface unrelated to diagnosis.

If a proposed feature is useful but does not pass this bar, it belongs outside the core gem.
