# Project Instructions: solid_lens

- Keep the gem focused on Solid Queue diagnostics only. Do not add UI/dashboard code in the MVP.
- Preserve the check pipeline: collector evidence -> check severity -> recommendation -> reporter.
- Prefer explicit, small checks over broad generic analyzers.
- Every new operational claim needs a test or a documented evidence source.
- Keep reports suitable for CI: deterministic JSON keys, stable finding ids, and non-zero exit only when requested.
