# Contract Versioning

SolidLens is a diagnostic gem, but its public surface is broader than Ruby
constants alone. CI wrappers, incident runbooks, and cheap-model tooling depend
on stable command and report behavior.

## Stable Public Surfaces

These surfaces are treated as intentional contract:

- command names: `doctor`, `profile`, and `explain`;
- stable finding ids such as `solid_queue.pool.undersized`;
- JSON report keys such as `command`, `summary`, `evidence`, and `findings`;
- supported public flags such as `--format`, `--output`, `--fail-on-high`,
  `--app-root`, `--rails-env`, `--duration`, and `--sample-interval`;
- the packaged product boundary note in `docs/specs/product-direction.md`.

## Release Rules

Patch releases may:

- fix incorrect findings, evidence, hints, or report rendering;
- improve docs, packaging, and release verification;
- tighten validation or redaction without removing supported fields.

Minor releases may:

- add new diagnostics or new finding ids;
- add new optional evidence fields;
- add new CLI flags or new public docs.

Minor releases can introduce new findings in existing apps. Release notes should
call out every new default diagnostic that can affect CI or operator workflows.

Major releases are required for:

- renaming or removing a public command;
- renaming or removing a released finding id;
- removing or incompatibly reshaping JSON fields;
- removing supported CLI flags;
- dropping supported Ruby, Rails, or Solid Queue ranges.

## Packaging Rule

The built gem must ship:

- `README.md`;
- `docs/contract-versioning.md`;
- `docs/specs/product-direction.md`.

Release verification must prove the packaged artifact, not only the checkout:

1. build the gem in isolation;
2. validate packaged public docs;
3. boot a disposable Rails host app against the packaged gem contents;
4. execute both `bundle exec solid_lens doctor` and
   `bin/rails solid_lens:doctor`.
