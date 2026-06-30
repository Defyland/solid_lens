# Technical Decisions

## 2026-06-29 - Build Causal Diagnostics Instead Of A Dashboard

Context: Solid Queue removes Redis from many Rails deployments but moves operational risk into the queue database. When a queue stalls, operators need to know which database-backed failure mode is responsible and what evidence proves it.

Options considered:

- Build a web dashboard for queue state.
- Build generic Active Job monitoring.
- Build a causal diagnostic toolkit for Solid Queue operational failures.

Choice: Build a causal diagnostic toolkit.

Pros:

- The gem stays focused on incident/debugging workflows.
- Every finding can point to evidence and an operator action.
- The project avoids duplicating APM, metrics, and admin UI products.
- CI use remains natural because reports are command-line artifacts.

Cons:

- It does not provide a persistent operational console.
- Teams still need their normal metrics stack for alerting and long-term graphs.
- Some users may expect a UI because queue tools often ship dashboards.

Consequences:

- New features must explain a Solid Queue failure mode or throughput risk.
- Product additions that require a dashboard or daemon belong outside the core gem.
- Documentation should keep the "not a dashboard" boundary visible.

Verification evidence:

- `docs/specs/product-direction.md`.
- `README.md` sections "Problem", "Why This Exists", and "Limits".
- `test/solid_lens/product_spec_test.rb`.

## 2026-06-29 - Preserve The Collector To Check To Reporter Pipeline

Context: SolidLens needs to inspect runtime state, queue topology, database schema, backlog tables, recurring schedule state, semaphores, claimed executions, bloat, and explain plans without mixing evidence collection with policy decisions.

Options considered:

- Let each check query the database directly.
- Put all logic in one large command object.
- Split evidence collection, finding generation, and report rendering.

Choice: Keep the pipeline `collector -> evidence -> check -> severity -> recommendation -> reporter`.

Pros:

- Collection failures can be represented as evidence and tested directly.
- Checks remain small and focused on one failure mode.
- Reporters can render the same report shape for humans and machines.
- The architecture scales by adding a collector or check without changing command behavior.

Cons:

- The evidence hash is a shared contract that must stay disciplined.
- A new diagnostic can require changes in both a collector and a check.

Consequences:

- Checks should not open new database connections or mutate tables.
- Collectors should not assign severity.
- Tests should cover both raw evidence and resulting findings for non-trivial diagnostics.

Verification evidence:

- `lib/solid_lens/runner.rb`.
- `lib/solid_lens/collectors/*`.
- `lib/solid_lens/checks/*`.
- `lib/solid_lens/reporters/*`.
- `test/solid_lens/*_collector_test.rb` and `test/solid_lens/*checks_test.rb`.

## 2026-06-29 - Keep Doctor, Profile, And Explain As Separate Diagnostic Modes

Context: Operators ask different questions in different moments. A pre-deploy check wants current readiness; an incident wants temporal growth; a database-bound investigation wants query plans.

Options considered:

- Provide one command that always collects every possible diagnostic.
- Provide many granular commands for every table and pathology.
- Provide three modes: `doctor`, `profile`, and `explain`.

Choice: Provide `doctor`, `profile`, and `explain`.

Pros:

- The command surface is small enough to remember.
- Expensive or time-based work is explicit.
- CI can run `doctor` without waiting for profile windows.
- Incidents can use `profile` and `explain` when those stronger signals are needed.

Cons:

- Users must choose the correct mode.
- Some findings appear only when the relevant mode collects enough evidence.

Consequences:

- New diagnostics should first decide which operator question they answer.
- The README and tests need to keep all three surfaces aligned.
- Rails commands, Rake tasks, and CLI paths must preserve the same mode behavior.

Verification evidence:

- `README.md` "Use Cases" and "Commands".
- `lib/solid_lens/runner.rb`.
- `lib/solid_lens/cli.rb`.
- `test/solid_lens/command_surface_integration_test.rb`.

## 2026-06-29 - Make Reports Suitable For CI And Cheap-Model Operation

Context: The broader backend-challenges goal is to build assets that can be evaluated and operated by cheaper models. For SolidLens, that means deterministic reports with stable ids, explicit evidence, and conservative exit behavior.

Options considered:

- Emit prose-only diagnostics.
- Exit non-zero whenever any finding exists.
- Emit structured JSON/Markdown with stable finding ids and explicit `--fail-on-high`.

Choice: Emit structured reports and require explicit failure gating.

Pros:

- CI can parse JSON without scraping Markdown.
- Markdown remains useful for incident notes.
- Stable finding ids make suppression, tracking, and model-driven triage possible.
- Default zero exit avoids breaking production debug commands unexpectedly.

Cons:

- Machine-readable output needs compatibility discipline.
- Teams must opt in to failure behavior with `--fail-on-high`.

Consequences:

- Finding ids are part of the practical public contract.
- JSON key shape should remain stable unless a release intentionally changes it.
- New reporters should render the same `Report` object instead of inventing alternate semantics.

Verification evidence:

- `lib/solid_lens/report.rb`.
- `lib/solid_lens/reporters/json_reporter.rb`.
- `lib/solid_lens/reporters/markdown_reporter.rb`.
- `test/solid_lens/reporters_test.rb`.

## 2026-06-29 - Use Bounded Profile Sampling Instead Of Continuous Monitoring

Context: Some Solid Queue failures only appear as growth or spikes over time. Continuous monitoring would move SolidLens toward daemon/APM territory, while a bounded sampling window keeps the tool useful during incidents without taking ownership of alerting.

Options considered:

- Only inspect current table state.
- Run a persistent background sampler.
- Provide a bounded `profile` command with duration, sample interval, deltas, and peaks.

Choice: Provide bounded profile sampling.

Pros:

- Operators can prove whether pressure is growing or only spiking.
- Reports capture temporal evidence without requiring a daemon.
- Sample cardinality can be capped for long windows.
- The tool stays easy to run in CI, staging, or incident shells.

Cons:

- It can miss behavior outside the chosen window.
- Long incidents still need external monitoring and alerting.
- Users must choose duration and sample interval responsibly.

Consequences:

- `profile` evidence must record requested interval, effective interval, sample limits, deltas, and peaks.
- Sampling should remain bounded and deterministic enough for report review.
- The README should frame `profile` as diagnostic evidence, not monitoring replacement.

Verification evidence:

- `lib/solid_lens/collectors/profile_collector.rb`.
- `lib/solid_lens/collectors/profile_evidence/*`.
- `test/solid_lens/profile_*_test.rb`.
- `README.md` "profile" behavior and "Limits".

## 2026-06-29 - Keep Adapter-Specific Query Plans Behind Explain Evidence

Context: Query-plan evidence is highly valuable when Solid Queue polling or dispatch looks database-bound, but `EXPLAIN` output differs across SQLite, PostgreSQL, MySQL, and MariaDB.

Options considered:

- Ignore query plans and only check indexes.
- Run one generic SQL explain path for every adapter.
- Add adapter-aware explain collectors/analyzers and expose them through `explain`.

Choice: Use adapter-aware explain evidence through `explain`.

Pros:

- Reports contain planner evidence that matches the actual database.
- SQLite, PostgreSQL, MySQL, and MariaDB can each use their native explain shape.
- Expensive/deep database diagnostics are explicit rather than hidden in every run.
- Wildcard queue discovery can be explained when it is the real bottleneck.

Cons:

- Integration coverage needs real database services for PostgreSQL and MariaDB branches.
- New adapters require explicit behavior instead of falling through silently.

Consequences:

- Adapter normalization belongs in collectors/analyzers.
- Checks should consume explain evidence without assuming one database's output shape.
- CI should keep dedicated database integration jobs where feasible.

Verification evidence:

- `lib/solid_lens/collectors/table_explain_collector.rb`.
- `lib/solid_lens/analyzers/explain_plan_analyzer.rb`.
- `test/solid_lens/explain_plan_analyzer_test.rb`.
- `test/solid_lens/postgres_integration_test.rb`.
- `test/solid_lens/mariadb_integration_test.rb`.

## 2026-06-29 - Treat The Packaged Command Surface As A Release Contract

Context: SolidLens already had strong checkout-based tests, but a public gem can
still fail after packaging if the built artifact drops docs, drifts from the
public command surface, or only works when the checkout is on disk.

Options considered:

- Rely on checkout tests plus manual `rake build` inspection.
- Verify only that the top-level gem can be required from the built artifact.
- Verify the built gem through a disposable Rails host app that exercises both
  the standalone CLI and the Rails command.

Choice: Verify the built gem through a disposable Rails host app.

Pros:

- Release confidence no longer depends on the checkout being present.
- The packaged gem proves both public execution surfaces, not only `require`.
- Public docs become part of the enforced release contract.
- Reviewers get a small, reproducible package-truth check.

Cons:

- Package verification adds extra runtime to CI and local release checks.
- The host-app smoke path needs maintenance when public command contracts
  intentionally change.

Consequences:

- `docs/contract-versioning.md` is shipped inside the gem.
- `package:verify` becomes the canonical package-truth gate.
- Public command changes must update the host-app smoke expectations

## 2026-06-29 - Ship Core Review Docs Inside The Built Gem

Context: SolidLens already teaches its product boundary, evidence pipeline, and
technical tradeoffs well in the repository. A reviewer or future maintainer who
only inspects the built gem currently loses that architecture and decision
surface, even though package audit already treats public docs as part of release
truth.

Options considered:

- Keep review docs only in the Git checkout.
- Publish the review story only in `README.md`.
- Ship the core review docs inside the built gem and enforce them in package
  verification.

Choice: ship `docs/architecture.md` and `docs/decisions.md` alongside the
already-packaged `docs/specs/product-direction.md` and
`docs/contract-versioning.md`, and verify that curated review-doc set during
package audit.

Pros:

- The release artifact teaches the product and architecture story directly.
- Reviewers can inspect reasoning from the packaged gem, not only from the
  checkout.
- Package verification now guards the didactic release surface against drift.

Cons:

- Public docs become a maintained release surface.
- Packaging changes must now account for documentation presence explicitly.

Consequences:

- `solid_lens.gemspec` must package the curated review docs.
- `SolidLens::PackageAudit::PUBLIC_DOCS` must fail if those docs disappear or
  contain local-only links.
- README evaluation instructions should point reviewers at the packaged-doc
  expectation directly.

Verification evidence:

- `solid_lens.gemspec`.
- `lib/solid_lens/package_audit.rb`.
- `test/solid_lens/packaging_test.rb`.
  intentionally.

Verification evidence:

- `lib/solid_lens/package_audit.rb`.
- `lib/solid_lens/package_audit/host_app_smoke.rb`.
- `test/solid_lens/packaging_test.rb`.
- `bundle exec rake package:verify`.
