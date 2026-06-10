# Rigor view (conformance)

[한국어](README_ko.md)

Question: **how faithfully does each implementation realize the Gateway API spec, and how well does it behave under measurement?**

It looks at both the **live measurement** aligned to the official spec (Support: Core/Extended × Channel: standard/experimental) and the **quality/non-functional metrics** that official conformance does not see.

## Outputs
- [`README_tables.md`](README_tables.md): the detailed tables (summary, per-item, canary quality, experimental, implementation matrix, non-functional, auth, flake), rendered directly on GitHub. This is the canonical output here.

> The pipeline also generates a styled single-page `report.html` (interactive) for the blog write-up. It is not committed here, since GitHub serves the data as Markdown and shows HTML only as source. Regenerate with `scripts/finalize.sh`.

## How this view differs from the official conformance suite
Official conformance is a **binary PASS/FAIL** self-declared by each implementation, and only looks at standard + experimental channel features. This view:
- **Measures, not declares**: it runs features directly on a live cluster and measures behavior.
- **Adds a quality axis**: canary 80/20 distribution convergence (cumulative pooled split), load success rate, robustness, and other metrics conformance does not measure.
- ⚠️ It is **our own data-path measurement** aligned to the official model, not an **official certification** in the upstream suite registry (agreement with the official v1.4.0 report confirmed against primary sources).

For the scoring criteria and freeze procedure, see `SCORING.md` and `rubric.yaml` at the project root. For the migration (starting-point) lens, see [`../migration-view/`](../migration-view/).
