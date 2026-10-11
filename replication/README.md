# Regression Replication and Income Counterfactuals

## Occupational-Position Harmonization and Salaried Robustness

`harmonize_occupation.R` corrects P6430 at input time without overwriting the
supplied microdata. The supplied file labels the raw codes using the old
questionnaire in every year. In the 2008--2019 framework, 7 denotes unpaid work
in other households, 8 day laborers, and 9 other workers. In the 2021--2025
Marco 2018 files used here, 7 denotes day laborers and 8 other workers.
The shared helper aligns the latter two categories with harmonized codes 8 and
9 and preserves the raw code separately. All estimators and microdata caches
include the harmonization version in their signatures.

The new mapping is documented in the [2025 questionnaire](https://microdatos.dane.gov.co/index.php/catalog/853/download/24257)
and [2025 data dictionary](https://microdatos.dane.gov.co/index.php/catalog/853/download/24735).
The old [2018 P6430 metadata](https://microdatos.dane.gov.co/index.php/catalog/608/variable/F2/V44?name=P6430)
document the previous coding. Some later catalog variable pages and the 2021
dictionary retain the old labels. We therefore also checked the original
2021 Marco 2018 microdata. In all twelve months, code 7 follows the employee
salary questions and code 8 the independent/other income questions. The
aggregate routing audit is in `salaried_output/raw_2021_routing_audit.csv`.
To repeat that source check, run `audit_occupation_codes.py` with the two
original 2021 semester ZIP paths. It writes only aggregate counts.

This correction affects pooled occupational-position controls, not merely
display labels. On 2026-10-11, all regression pipelines and income scenarios
were rerun. The full-sample preferred 101+/solo premium changes from 37.1873
to 37.1271 percent among informal workers and from 16.5218 to 16.4893 percent
among formal workers. Annual profiles are unchanged because the recoding only
renames categories within a year. `salaried_output/harmonization_impact.csv`
and `unaffected_model_checks.csv` record these comparisons. The October 10
reconciliation below is a historical record, not a claim that the subsequent
coding correction leaves all pooled coefficients identical.

After `reconcile_regressions.R` and `preferred_extensions.R`, run:

```sh
Rscript --vanilla replication/salaried_robustness.R
python replication/build_salaried_table.py
python replication/validate_salaried_robustness.py
```

Salaried workers comprise private-sector employees, government employees,
domestic workers, and day laborers. Both formality groups are retained. The
restricted model uses the preferred controls, weights, fixed-effect structure,
and sector-department clustering, with 11--19 as its fitted reference. It
contains 2,682,009 observations and 555 clusters after removing 66 additional
singleton cells. The table compares this model with the corrected full sample.
CSV contrasts additionally provide solo and 101+ references and sector-clustered
inference. A second fit with solo as the reference independently verifies the
contrasts and standard errors. The Python validator reconstructs them using
the full covariance matrices and checks every displayed coefficient and S.E.
These are sample-sensitivity comparisons, not causal decompositions.

For a complete rebuild, run the regression table updater before
`income_counterfactuals.R`, then build its tables before running
`validate_regression_outputs.py`. That validator checks agreement between
the regression and income-scenario outputs from the same harmonization version.

## Preferred-Model Extensions

The main results now use the preferred controls for within-formality premiums,
formal-informal gaps, dynamics, and approximate elasticities. The earlier
sector-year specifications remain reproducible comparisons in the appendix.
After the synchronized regression steps below, run:

```sh
Rscript --vanilla replication/preferred_extensions.R /path/to/Paper-GEIH_base_modelo_personas_2008_2025.dta
python replication/build_preferred_tables.py
Rscript --vanilla replication/plot_preferred_extensions.R
python replication/validate_preferred_extensions.py
```

`preferred_output/` contains aggregate coefficients, selected full covariance
matrices, profiles, endpoint changes, elasticities, and clustering checks.
Local model caches in `build/preferred_extensions/` and the aggregate RDS files
are excluded from Git. The script verifies that the pooled preferred model
reproduces the coefficients and covariance matrix from `reconcile_regressions.R`.
The income scenarios must be regenerated whenever those coefficients change.

- The common estimation sample excludes singleton sector-department-year cells
  and contains 5,268,375 observations. Control-set comparisons use this same
  sample so changes in inference do not reflect a sample change.
- Annual regressions include all preferred controls and allow all slopes to
  vary across years. They are the blockwise estimate of the fully year-interacted
  extension. This avoids constructing a large, mostly zero full-period design
  matrix while retaining the intended year-specific conditional comparisons.
- A joint 2008/2025 model interacts every non-fixed-effect regressor with the
  endpoint indicator. Its coefficients reproduce the separate endpoint fits.
  Tests of changes use the joint covariance matrix, not independence between
  years or overlapping confidence intervals. The table reports differences
  between percentage premiums in percentage points, while p-values test zero
  differences between their underlying log contrasts.
- The baseline covariance clusters by sector-department, with an additional
  sector-clustering sensitivity on the identical fitted coefficients. In the
  pooled preferred model the formal 101+/solo p-value is below 0.001 under the
  former and 0.113 under the latter. The informal 101+/solo endpoint-change
  p-values are 0.011 and 0.090. The manuscript reports this sensitivity.
- Preferred elasticities by formality are contrasts from one log-size-by-formality
  interaction regression, not separate regressions. The older separate-sample
  estimates remain in the comparison appendix. Assigned size values remain
  1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, and 150.
- All tests are two-sided. Endpoint tests are pointwise and not adjusted for
  multiple comparisons. The annual, pooled, and endpoint regressions use their
  respective cluster counts, rather than borrowing one degree-of-freedom value.

The independent validator reconstructs contrasts from the exported coefficient
and covariance matrices, recalculates t tests and confidence intervals, checks
endpoint/annual equivalence, and checks the manuscript's references, bilingual
figure paths, and preservation of the approved abstract.

## Quadratic Approximation with Preferred Controls

After `preferred_extensions.R`, run:

```sh
Rscript --vanilla replication/quadratic_preferred.R /path/to/Paper-GEIH_base_modelo_personas_2008_2025.dta
python replication/build_quadratic_tables.py
Rscript --vanilla replication/plot_quadratic_preferred.R
python replication/validate_quadratic_preferred.py
```

This exercise estimates only a quadratic, not a cubic or spline. Each model
interacts log assigned size and its square with formality in one regression.
It retains the preferred sample, controls, weights, fixed effects, and clustering.
The baseline size assigned to 101+ is 150, with 101 and 250 as sensitivity checks.
Other bin assignments are unchanged. The profile is anchored at solo work because
log(1) is zero. Fair and Dominguez (1991) motivate the polynomial restriction,
but their sum-zero normalization is not imposed in addition to our reference.

The unrestricted categorical model supplies the Wald tests. For each formality
group, the eight log contrasts must lie in the span of log assigned size and its
square, giving six linear restrictions. The joint test imposes twelve. Tests use
the full contrast covariance, including formal-informal covariance in the joint
test, and an approximate F(q, G-1) distribution. Both sector-department and sector
clustering are reported, with 559 and 17 clusters, respectively. They are not
tests that the quadratic coefficient alone is zero.

`quadratic_output/` contains aggregate coefficients, covariance matrices, curves,
category predictions, restriction tests, and provenance. Model caches and all
microdata remain excluded from Git. The independent Python validator reconstructs
all predictions and intervals and repeats the Wald tests using a different
restriction matrix based on two anchor categories rather than R's QR basis.
The bilingual figure overlays the baseline quadratic with the preferred
categorical estimates. Confidence bands are pointwise and conditional on the
assigned sizes. The older sector-year quadratic files remain reproducible
historical outputs, but are no longer included in the paper.

## Synchronized Regression Outputs

The comparison tables and figures are generated from one estimation
run, using the same harmonized input file as the preferred extensions. The three reference categories are
linear contrasts of each fitted model, not independent data-processing runs.
Run these steps in order:

```sh
Rscript --vanilla replication/reconcile_regressions.R /path/to/Paper-GEIH_base_modelo_personas_2008_2025.dta
python replication/validate_regression_outputs.py
python replication/update_regression_tables.py
Rscript --vanilla replication/plot_reconciled_regressions.R
Rscript --vanilla replication/check_descriptive_reference.R
python replication/validate_regression_tables.py
```

The R scripts require `haven`, `dplyr`, `fixest`, `ggplot2`, and `scales`.
The independent Python validator requires `scipy`. The table updater uses only
Python's standard library and changes numerical rows without replacing captions
or explanatory notes. English and Spanish figures are generated together.

Aggregate coefficients, contrasts, sample fingerprints, input-file fingerprint,
package versions, and validation checks are saved in `regression_output/`.
All tests are two-sided and use the model's cluster-based Student t degrees of
freedom, including linear combinations and transformed confidence intervals.
The script checks that changing only the clustering convention leaves the point
estimates unchanged. It also re-estimates selected models with a different base
to verify the algebraic contrasts and their standard errors independently.

`build/regression_sample.rds` is a local microdata cache and is excluded from Git.
It must not be published. Delete this cache after changing sample-construction
code. Its signature includes input size, modification time, and the occupational
harmonization version and invalidates it when any of these change.

The optional second argument to `reconcile_regressions.R` is a historical input
file for diagnosing old outputs. It is not used to generate the current tables.
This optional diagnostic also requires the archived interaction-coefficient CSV
in the sibling CJC-Monitor checkout.

### Numerical Reconciliation on 2026-10-10

The old sector-year interaction table reproduced a historical data file with
5,154,213 estimation observations. The current file gives 5,268,514 observations
for the same specification. Re-estimating the old input reproduced all eight
archived informal coefficients to numerical precision, identifying mixed data
versions as the source of the coefficient discrepancy. The historical input's
SHA256 is `908ad64d932c204f697932cc0ce86bedcb88c0abd829ad33aa6eddfb85067112`.
The current input's SHA256 is
`4d5132a74396cf91fc3ee180905d8dab5d17c082ac83099383ecf4a52d2720ef`.
See `regression_output/historical_data_check.csv` for the direct comparison.

There was a separate inference inconsistency. Some hand-built contrasts used
normal critical values, whereas coefficient tables used cluster-based t tests.
All regression contrasts now use the latter convention, including 16 degrees
of freedom for the 17-sector comparison models. The preferred specification has
559 sector-department clusters and 558 degrees of freedom. Earlier geographic
columns without singleton removal have 561 clusters and 560 degrees of freedom.

The 19 regression tables were regenerated together. Six associated figures were
regenerated in both languages, and the results text was synchronized. The
preferred coefficients and standard errors reproduce their previous values
within `1e-7`, so the income scenarios and the abstract's main magnitudes do not
change. The earlier editorial audit is a historical record. Its numerical
pending item is resolved by this reconciliation.

## Illustrative Income Counterfactuals

The exercise applies the preferred pooled size-by-formality model to the 2025 estimation sample. It includes sex, age, age squared, education, occupational-position controls, and sector-department-year fixed effects. Estimation uses GEIH expansion weights and sector-department clustering.

## Reproduce

1. Obtain the harmonized `Paper-GEIH_base_modelo_personas_2008_2025.dta` using the original GEIH preparation pipeline. This file and the raw DANE microdata are not included here. The original pipeline is in the [CJC-Monitor repository](https://github.com/Kin-George/CJC-Monitor). This folder is not a replacement for that data-construction pipeline.
2. With R packages `haven`, `dplyr`, and `fixest` installed, run from this repository:

```sh
Rscript --vanilla replication/income_counterfactuals.R /path/to/Paper-GEIH_base_modelo_personas_2008_2025.dta
python replication/build_counterfactual_tables.py
```

The R script takes an optional second argument for the output directory. The Python script accepts the same directory as its optional first argument. Its default is `replication/output`. The Python step can regenerate the manuscript tables from the committed aggregate outputs without access to microdata.

The R script first verifies its eight informal and eight formal size coefficients and their standard errors against column (4) in `Paper/tables/regression_local_geography_formality_robustness.csv`. The preferred estimation sample has 5,268,375 observations and 559 sector-department clusters. The 2025 simulation sample has 341,282 observations. The Python step independently reconstructs all six unrestricted scenarios for both baselines and both denominators from the 18 size-formality groups.

## Interpretation

- Baseline hourly income is exponentiated fitted log income times a common survey-weighted smearing factor, computed from 2025 residuals. The factor cancels from percentage changes. This assumes a common exponential residual moment, not a destination-specific residual distribution.
- Each worker receives the estimated destination-to-origin wage multiplier. Weekly income is hourly income times unchanged weekly hours. Aggregate changes use weighted sums of weekly income, not means of individual percentage gains.
- Target-group denominators include members already in the destination. All-worker denominators include the entire 2025 sample. Expansion-weight sums are not reported as counts of unique annual workers.
- The observed-baseline sensitivity preserves each worker's log residual and multiplies observed income by the same conditional wage ratio.
- The maximum-profile scenarios select 101+ for formal workers and 51--100 for informal workers. These destinations are common within each group under the additive model, not worker-specific comparative advantages. They are selected from estimated coefficients.
- Support screens count destination observations by sector, department, occupational position, size, and formality. Workers who fail a screen remain at origin. Smaller totals then partly reflect fewer moves, not new regression estimates. No eligible moves is distinct from a zero estimated return.
- The extra intervals saved in `scenario_results.csv` propagate only contrast-coefficient uncertainty, holding baseline income predictions, composition, hours, weights, and destinations fixed. They are not full sampling intervals and are not reported in the manuscript tables. Maximum-profile frequencies are coefficient-draw frequencies, not probabilities of policy optimality.
- These are conditional income scenarios. They do not estimate causal effects, equilibrium reallocations, output gains, productivity losses, or welfare.

## Data Handling

`private_cache/` contains working observations and must not be published. Detailed destination-cell counts, occupational-position cell counts, and local metadata are also excluded from version control. The committed outputs contain aggregate scenario results and validation checks only.

The manuscript reference model was at commit `081a61eb090da23b4927168863bef7286c15667c` when this exercise was verified. R 4.5.2 was used. Package versions and the input size, modification time, and reference-table hash are recorded in the local run metadata and cache signature.
