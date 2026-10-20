# Academic presentation

Compile `presentacion_javeriana.tex` at the repository root in Overleaf.
The main talk is in English and has 18 slides for a 20-minute presentation,
followed by 10 minutes for questions. Backup slides retain all paper figures and tables.
The appendix is excluded from the main-talk slide denominator.
The `\source{...}` annotations remain in the TeX for traceability but are not
displayed in the PDF. Regression interpretation notes and appendix table notes
remain visible.

## Main talk and questions

The main talk has no section-divider or separate closing slide. Leave the
conclusions (slide 18) visible when questions begin.

Shortening means selecting which slides to present, not deleting the others.
Consider both the main talk and existing backup slides when making the selection.
Keep unselected slides after the conclusions. The overview, motivation, full
data slide, roadmap, and contact slide also remain available there.

| Slides | Content | Suggested time |
| --- | --- | --- |
| 1--3 | Question, data, and definitions | 2 minutes |
| 4--7 | Employment, hourly income, formality, and worker composition | 4 minutes |
| 8--12 | Sequential controls, preferred model, minimum wages, and conditional comparisons | 6 minutes |
| 13--14 | Dynamics | 4 minutes |
| 15--16 | Income scenarios and results | 2 minutes |
| 17--18 | Interpretation, policy, and conclusions | 2 minutes |

`backup_talk_details.tex` retains the additional descriptive figures, full
variable definitions, detailed regression output and equations, and scenario
support checks. `backup_figures.tex` retains the salaried-worker exercise and
other comparison specifications. All paper tables follow in the final appendix.
The international elasticity comparison follows the approximate-elasticity
specification in `backup_talk_details.tex`.

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

The main results proceed from the sequential-controls table to the preferred
formality interaction with geographic and occupational controls. The intermediate
geographic-control table and detailed equations are available for questions.
Paper references in slides use `\paperref{label}`. The exporter obtains their
numbers from `build/main.aux`, so moving paper tables does not require manually
renumbering the slides. The main-talk table aliases are also label-based.

Generated files are committed so Overleaf needs neither Python nor the raw
microdata. Figures remain linked to the same English assets used in the paper.

Bootstrap results are temporarily omitted from both PDFs. The original summary
slide is retained in `backup_bootstrap.tex`, without an active input. Its table
is still generated from `replication/inference_audit_output/wild_bootstrap.csv`.
The paper's bootstrap table and replication outputs are also retained.
The income summary uses
`replication/output/scenario_results.csv` and distinguishes the change in mean
weekly income among reassigned workers from the change in total weekly income
across all workers. These source hashes are recorded in `coverage.json`.
The sector figure is displayed across two slides using the current vector PDF,
with the shared size axis and bubble legend repeated for the upper panels.
