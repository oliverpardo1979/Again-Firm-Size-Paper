# Replication

## Current Data and Results

The manuscript uses the corrected primary-job-income sample adopted on October
21, 2026. Earlier replication notes are retained in
[HISTORICAL_REPLICATION.md](HISTORICAL_REPLICATION.md). Their numerical results
refer to earlier data definitions and must not be read as current estimates.

The current sample includes all twelve months in 2008-2019 and 2021-2025,
workers aged 15-120, positive observed main-job income, positive usual weekly
hours in the main job (at most 168), positive weights, and complete controls.
There are 5,426,316 complete records. Removing fixed-effect singletons leaves
5,426,174 observations in the preferred full-sample model and 2,765,713 in the
salaried model.

Primary monthly income sums P6500, P6590S1, P6600S1, and P6750, with sentinel
values 98 and 99 treated as missing. A row with all components missing remains
missing. P7070, the second-job component, is excluded. No new income imputation
is performed. Hourly income uses usual main-job hours, and the annual price
factors in `primary_income_output/price_factors.json` retain the paper's
end-of-year CPI conversion to 2025 pesos.

The weights are DANE's retrospective CNPV 2018 population factors in 2008-2009,
official frame-bridge/empalme factors in 2010-2019, and native marco 2018 factors
in 2021-2025. The empalme factors must not be replaced by bare retrospective
population factors. DANE's adjustment also addresses the change in sampling
frame. Monthly weights divided by 12 give annual-average worker counts.

Original person keys are used to join income, characteristics, and weights.
Cabecera and resto modules are mutually exclusive. Area modules are not added
again to cabecera. All merges require unique person-month keys and complete
matches. Occupational codes are aligned before selecting salaried workers,
who comprise private employees, government employees, domestic workers, and day
laborers. The Stata data label identifies already-aligned codes so that
`harmonize_occupation.R` does not recode them a second time.

## Public Microdata

Obtain the original archives from DANE's
[GEIH catalog](https://microdatos.dane.gov.co/).
The relevant source families are:

- 2008 and 2009 monthly SAV archives, plus each year's CNPV 2018 weight supplement.
- Official GEIH empalme annual ZIPs for 2010-2019.
- The two marco 2018 semester ZIPs for 2021.
- Monthly GEIH ZIPs for 2022-2025.

Place them in a local directory and set `GEIH_RAW_DIR` to that directory.
Expected filenames are `SAV_GEIH_YEAR_MM.zip`, `GEIH_Empalme_YEAR.zip`,
`GEIH_2021_marco2018_I.zip`, `GEIH_2021_marco2018_II.zip`,
`GEIH_YEAR_MM.zip`, and `Fex proyecciones CNPV 2018_YEAR.zip`.
The 2008 and 2009 SAV conversion avoids income fields absent from some of the
parallel CSV releases. Source validation summaries and coverage counts are in
`primary_income_output/`. Individual observations are never committed.

From this repository, run:

```text
python replication/prepare_historical_sav.py 2008 2009
Rscript --vanilla replication/convert_historical_sav.R .. 2008 2009
python replication/reconstruct_primary_income.py
python replication/build_primary_input.py data/primary_records
```

The historical converter's first argument is the parent directory, used only
to locate an optional local R package library. Standard installed R packages
also work. Python requires pandas and numpy. R requires haven, dplyr, fixest,
ggplot2, scales, tidyr, readr, and stringr. Numerical validation also uses scipy.

The resulting `data/GEIH_primary_income_2008_2025.dta` is the default input
to the current estimators. Raw archives, annual records, and the Stata file are
excluded from Git and must not be synced through Overleaf.

## Estimation and Rendering

```text
python replication/run_primary_revision.py --rscript /path/to/Rscript
python replication/primary_worker_profiles.py data/primary_records
```

The runner refreshes common-premium specifications, geographic and occupation
controls, size-by-formality interactions, alternative reference categories,
annual and joint-endpoint models, salaried models, elasticities, quadratics,
income scenarios, conventional clustering comparisons, and manuscript figures
and tables. It does not edit narrative prose or presentation sources.
Descriptives are staged in `build/descriptive_refresh/` before their numerical
rows are transferred to the edited manuscript tables, preserving captions,
notes, and grouping.

The minimum-wage ridgelines use weighted Gaussian kernel densities of the
log2 hourly-income ratio, with a common bandwidth of 0.12. Each curve is
rescaled to the same peak height. The curves show distributional shape, not
relative population mass. Separate share labels report each size category's
weight within its formality group.

The 2025 worker-profile script also uses `GEIH_RAW_DIR` to verify detailed
activities against the original person keys. It supersedes the historical
`audit_formal_solo_education.R` for the corrected sample.

All contrasts use the full coefficient covariance matrix and two-sided tests.
Annual models allow all slopes to vary by year. Endpoint tests use joint
fully interacted 2008/2025 fits. Coefficients and samples stay fixed across
clustering conventions. Quadratics stop at degree two.

The income calculations use each sample's own preferred coefficients and 2025
population. The full-sample coefficients applied to salaried workers provide a
separate composition comparison. Workers already at the destination retain
their baseline predictions. All-worker totals and reassigned-worker means have
different denominators. The common retransformation factor cancels from ratios.

Wild-bootstrap files are historical and omitted from the manuscript. They have
not been recalculated for this sample. The current runner refreshes conventional
inference only. Do not combine the old bootstrap results with current estimates.

## Validation

```text
python replication/validate_regression_outputs.py
python replication/validate_regression_tables.py
python replication/validate_preferred_extensions.py
python replication/validate_salaried_robustness.py
python replication/validate_salaried_extensions.py --manuscript
python replication/validate_quadratic_preferred.py
python replication/inference_audit_validate.py
```

These checks independently reconstruct contrasts, covariance-based standard
errors, p-values, confidence intervals, and income ratios from aggregate
outputs. They check reference invariance, sample counts, table values, equation
references, and consistency of the two abstracts. The separate approved
pre-adoption audit provides another comparison against the integrated pipeline.

Compile `main.tex` for the author version and
`manuscript_no_author_details.tex` for the anonymous version. Both use the same
section and figure files. The title page remains separate.
