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

## Software Environment

Use a separate Python virtual environment. The tested environment used Python
3.12.14. [requirements-tested.txt](requirements-tested.txt) pins the observed
versions of numpy, pandas, scipy, and Pillow used by the numerical pipeline,
validators, and image checks. It records direct dependencies, not a complete
transitive lock file. From the repository root on Windows:

```powershell
py -3.12 -m venv .venv
& '.venv/Scripts/python.exe' -m pip install -r replication/requirements-tested.txt openpyxl==3.1.5
& '.venv/Scripts/Activate.ps1'
```

The `python` commands below refer to this environment. Without activation,
invoke `.venv/Scripts/python.exe` explicitly. The local, untracked
`build/qa_dependencies/` directory is not a replication requirement. The pins
match the installed libraries used for validation, but installation into a new
virtual environment has not been tested in this audit.
The official CPI workbook validator additionally requires openpyxl. The command
above pins its observed installed version, 3.1.5.

R requires haven, dplyr, fixest, ggplot2, scales, tidyr, readr, and stringr.
Install them in a standard R library or supply an absolute library directory
through `R_LIBS_USER`. The sensitivity outputs record its tested R and package
versions separately.

## Public Microdata

Obtain the original archives from DANE's
[GEIH catalog](https://microdatos.dane.gov.co/).
The relevant source families are:

- 2008 and 2009 monthly SAV archives, plus each year's CNPV 2018 weight supplement.
- Official GEIH empalme annual ZIPs for 2010-2019.
- The two marco 2018 semester ZIPs for 2021.
- Monthly GEIH ZIPs for 2022-2025.

The complete inventory of the 86 archives used in the all-year reconstruction
is [raw_source_manifest.json](primary_income_output/raw_source_manifest.json).
It records each filename, DANE source URL, file size, and SHA256 hash. The legacy
`downloaded_source_manifest.json` covers only 69 of these 86 sources and is not
the complete inventory.

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
also work. Use the software environment described above for reconstruction,
estimation, and numerical validation.

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

For a fresh reconstruction, use a separate checkout and output directory. After
rebuilding all annual records and the Stata input, run the following command
with the five paths replaced by the actual locations:

```text
python replication/validate_reconstruction.py --records /path/to/clean/data/primary_records --rebuilt /path/to/clean/data/GEIH_primary_income_2008_2025.dta --baseline /path/to/adopted/data/GEIH_primary_income_2008_2025.dta --source-dir /path/to/assembled/raw --output /path/to/clean/build/reconstruction_validation
```

All five arguments are required. This validator compares every rebuilt record
and column with the adopted Stata input in chunks, checks the fresh annual
coverage and attrition for all 17 years and 204 months, and hashes the source
ZIPs. Its output is separate from the adopted baseline. A successful estimator
run from processed data does not establish successful reconstruction from raw
archives. The historical `validate_primary_revision.py` instead compares with
the pre-adoption audit, imports its coverage summaries, and checks reconstructed
records only for 2025. These are different validation scopes.

The completed independent rebuild from local copies of the 86 DANE archives
reproduced all 5,426,316 records and all columns of the adopted input at
`rtol=1e-12` and `atol=1e-10`, covering all 204 months. This validates
reconstruction from the local archive copies, not a fresh network download
or the current availability of the recorded URLs.

The reconstruction also writes `income_selection_YEAR.csv` with observed,
all-missing, and nonpositive income counts among employed, age-eligible
respondents, grouped by salaried status, formality, and firm size. These
diagnostics describe selection without changing the adopted sample definition.

Validate the annual price factors against the downloaded DANE national CPI
workbook with:

```text
python replication/validate_price_factors.py /path/to/anex-IPC-Indices-sep2026.xlsx --source-url https://www.dane.gov.co/files/operaciones/IPC/sep2026/anex-IPC-Indices-sep2026.xlsx --output /path/to/cpi_validation
```

The workbook path, source URL, and output directory are required. The check uses
December index levels and compares each adopted factor with the 2025 index
divided by that year's index. The retained `integral_audit_output/cpi_validation.csv`
and `cpi_source.json` record all 17 levels and factors, the source URL, and the
workbook SHA256. Their maximum absolute factor difference is below `1e-12`.

After the clean estimation pipeline finishes, compare only its newly generated
CSV outputs with the retained reference checkout:

```text
python replication/validate_output_replication.py --replica /path/to/clean --reference /path/to/adopted --output /path/to/clean/build/output_validation --since-epoch RECORDED_UTC_START_EPOCH
```

All four arguments are required. Record the clean run's UTC Unix start time
before launching it and pass that value to `--since-epoch`. The validator uses
`rtol=1e-9` and `atol=1e-7`, listing older or copied CSVs as not tested. It does
not establish that those older assets were regenerated, and it does not compare
model-cache or PDF bytes.

`regression_output/previous_table_comparison.csv` compares newly estimated
coefficients and standard errors with the manuscript tables present before
the table updater runs. It is a run-relative diagnostic, not a comparison
between independent estimation runs. The original primary-income adoption
differences are preserved in
`regression_output/historical_primary_adoption_table_comparison.csv` and are
excluded from current replication evidence. The current diagnostic records
agreement with the adopted tables up to floating-point precision.

For the adopted estimation outputs, run:

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

## Archived 2010-2025 Period Sensitivity

This exploratory check is retained for the audit record but is excluded from
the manuscript and presentation at the author's request. The main comparison
remains 2008-2025. Its scripts and outputs are not part of the main replication
sequence.

This separate exercise drops 2008-2009 while retaining 2010-2019 and 2021-2025.
It uses the adopted processed input, not a new reconstruction of the raw
archives. It does not replace the 2008-based manuscript results. Income, prices,
hours, occupation codes, formality, firm-size categories, and weights are
unchanged. In particular, monthly weights remain divided by 12.

Run from this repository with R packages installed in a standard library or an
absolute directory supplied through `R_LIBS_USER`. For the existing Windows
workspace library:

```powershell
$env:R_LIBS_USER = (Resolve-Path '../CJC-Monitor/.Rlib').Path
& 'C:/Program Files/R/R-4.5.2/bin/Rscript.exe' --vanilla replication/period_sensitivity.R
python replication/validate_period_sensitivity.py
python replication/build_period_sensitivity_table.py
```

The final command renders the retained, unreferenced
`Paper/sections/period_sensitivity_table.tex` from the validated endpoint
outputs. Neither document includes this table. The command does not estimate
additional models or replace the 2008-based results.

Use the Python environment described above for validation and table rendering.
The R script requires haven, dplyr, and fixest. It fixes estimation and numerical
thread settings at two. An optional first positional argument supplies another
path to the identical adopted Stata file, whose MD5 must match the baseline
provenance. It does not read baseline model caches. The baseline aggregate CSVs
remain read-only references for sample checks and comparisons.

The script estimates exactly four models: a pooled preferred model and a joint,
fully interacted 2010/2025 model for each of the full and salaried samples.
Both retain Solo as the reference, the preferred controls and fixed effects,
and sector-department clustering. Sector-clustered inference uses the same
fits. There are 4,839,346 complete full-sample records and 2,476,870 complete
salaried records. Separate singleton exclusions leave 4,839,217 and 2,476,733
estimation observations. Joint endpoints use 653,437 and 335,655 observations.

Annual profiles for retained years are reused because those regressions are
estimated separately by year. Their sample counts and joint-endpoint point
estimates are checked against the adopted annual outputs. The new endpoint
standard errors come from the joint fits, preserving cross-year covariance.
Changes over 2010-2025 and 2008-2025 cover different intervals and are not
tests of the same endpoint contrast.

The four existing 2025 scenarios use each sample's newly fitted pooled
coefficients and fixed effects, retaining its original 2025 workers, hours,
and weights. Outputs distinguish all-worker totals, reassigned-worker means,
and target-group totals. The separate `Salaried_full_coefficients` rows apply
the new full-sample predictions to salaried workers as a composition comparison.
Only unrestricted, predicted weekly-income scenarios are recalculated here.
The common retransformation factor cancels from all reported gains. This
exercise adds no bootstrap, model families, or scenario confidence intervals.

Aggregate outputs are written only to `replication/period_sensitivity_output/`.
Private fitted-value caches and local environment details are written only to
`build/period_sensitivity/`, which is excluded from Git. Cache keys include the
input hash, retained years, script and occupation-harmonization hashes, model,
formula, sample count, and R/package versions. Removing only this exercise's
four model RDS files forces its four fits to run again.

`validate_period_sensitivity.py` reconstructs estimates, standard errors,
two-sided t tests, confidence intervals, and income ratios from the exported
coefficients, full covariance matrices, and origin-destination aggregates. It
also checks populations, monthly coverage, annual/joint consistency, unchanged
nonmovers, and baseline reference hashes. It writes `validation.json` and three
baseline-comparison CSVs only in the sensitivity output directory.
It also exports precise endpoint test statistics and the informal-minus-formal
101+/Solo log-premium contrasts in 2010, in 2025, and in their change, using
the existing joint covariance matrices without additional fits. These contrasts
compare size premiums, not formal-informal income levels. The local saved-fit
audit in `build/period_sensitivity/check_saved_fits.R`, when available, checks
the original 2010 fit coefficients, standard errors, and p-values and exports
independent R calculations. The Python validator cross-checks these audit
receipts when present. They are not required to run the four-fit sensitivity
on another machine.
`package_versions.csv` and `provenance.txt` record the actual R runtime and
loaded package versions, including package build versions. `validation.json`
records the Python and numerical-package versions. These receipts describe the
run actually performed and do not claim fresh raw-data replication.
