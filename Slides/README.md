# Academic presentation

Compile `presentacion_javeriana.tex` at the repository root in Overleaf.
The main talk is in English. Backup slides retain all paper figures and tables.
The appendix is excluded from the main-talk slide denominator.

## Updating the evidence

1. Compile the latest `main.tex` to `build/main.pdf` and `build/main.aux`.
2. Run `python replication/build_presentation_assets.py`.
3. Update the narrative and selected results in `Slides/main_results.tex`.
4. Run `python replication/validate_presentation.py`.
5. Compile the presentation, check the log, and inspect rendered slides.

`Slides/generated/` contains native LaTeX tables exported from the paper's
included table files, not new estimates. Parenthesized standard errors use a
smaller font than coefficients. Long tables are split into consecutive slides.
`coverage.json` records all figure files, table sources, labels, paper numbers,
and source hashes. Unreferenced or silenced paper tables are not exported.

The main results proceed from sequential worker controls to geographic and
occupational controls, and then to the preferred formality interaction.
Paper references in slides use `\paperref{label}`. The exporter obtains their
numbers from `build/main.aux`, so moving paper tables does not require manually
renumbering the slides. The main-talk table aliases are also label-based.

Generated files are committed so Overleaf needs neither Python nor the raw
microdata. Figures remain linked to the same English assets used in the paper.

The main-talk bootstrap summary is generated from
`replication/inference_audit_output/wild_bootstrap.csv`. The income summary uses
`replication/output/scenario_results.csv` and distinguishes the change in mean
weekly income among reassigned workers from the change in total weekly income
across all workers. These source hashes are recorded in `coverage.json`.
The sector figure is displayed across two slides using the current vector PDF,
with the shared size axis and bubble legend repeated for the upper panels.
