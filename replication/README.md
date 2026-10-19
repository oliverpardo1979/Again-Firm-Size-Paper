# Regression Replication and Income Counterfactuals

## Sector Income Figure

`Rscript --vanilla replication/plot_sector_income.R` regenerates Figure 5 in
English and Spanish, as PNG and vector PDF files. It uses the unchanged
aggregate cells in `Paper/tables/descriptive_wage_by_sector_year_size.csv`,
exported by `Code/02.4_PaperDescriptives.R` in CJC-Monitor and used in the
previous four-column figure. No microdata are needed for this layout update.
The script preserves the sector order, income means, employment shares, and
separate income scales by sector. It checks the endpoint comparisons quoted in
the text. Bubble areas represent employment shares within each sector-year.
The manuscript uses the vector version, sized for a full-page two-column
layout with readable type at the final printed size.

## Own-Account Workers in 101+ Units

`Rscript --vanilla replication/audit_own_account_large_firms.R` profiles
own-account workers in the 101+ category in 2025. An optional first argument
specifies the paper's input DTA. It matches the descriptive-table sample before
regression singleton exclusions and verifies the three own-account shares in
Table 4 against raw occupational code 4. Only aggregate outputs are saved in
`own_account_output/`. Composition percentages use survey weights, while
observation counts are unweighted survey records, not population totals.
Detailed categories with fewer than 20 observations within a formality group
are pooled for export.

There are 10,547 formal and 770 informal own-account observations in 101+ units.
The formal group accounts for 9.6 percent of formal workers in 101+ units.
Within this group, 45.7 percent work in public administration and defence,
20.3 percent in health and social assistance, and 13.0 percent in education.
Their mean age is 38.2 years, 55.7 percent are women, and 85.6 percent have higher
education. Mean hourly income is 23,010 pesos of 2025. The less numerous
informal own-account group has a different composition, led by arts, recreation
and other services (23.2 percent) and transport and storage (15.5 percent).

The [2025 GEIH manual](https://microdatos.dane.gov.co/index.php/catalog/886/download/24400)
classifies public- and private-sector service contractors as own-account workers
(printed pages 89--90). Page 115 permits non-solo sizes for partnerships,
unpaid family assistance, and public- or private-sector contractors, and
explicitly assigns state contractors to 101+. These instructions explain why
own-account status and large-unit size are not inherently inconsistent.
The paper input does not retain a contractor indicator or the original
independent-work arrangement question. Its `ocupacion` variable repeats
occupational position rather than providing a detailed profession.
The sector profile is consistent with service contracting but cannot establish
the share of contractors or distinguish public from private providers in health
and education. No observations are recoded or removed on this basis.

## Formal Solo Workers by Education

`Rscript --vanilla replication/audit_formal_solo_education.R` reproduces the
additional breakdown accompanying Table 4 and in the presentation's U-shape
slide. An optional first argument specifies the paper's input DTA. The script
uses the 2025 descriptive sample of formal solo workers. It compares those with
and without higher education, and reports selected activities within the former
group. Own-account shares are within each education group. The selected activity
shares use formal solo workers with higher education as the denominator. Income is measured
per hour in 2025 pesos. Only aggregate outputs are saved in `formal_solo_output/`.
The checks reproduce the reported education and own-account shares and both
income means. Activity codes 6910 and 6920 identify legal and accounting
services in the [DANE CIIU classification](https://www.dane.gov.co/files/sen/nomenclatura/ciiu/CIIU_Rev_4_AC2021.pdf).
They describe economic activities, not each worker's individual profession.
No regression or sample definition changes in this exercise.

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
Rscript --vanilla replication/plot_salaried_robustness.R
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

The table is in the main results, immediately before Dynamic Results. Its
summary rows distinguish the 101+/solo comparison from the full size profile.
`salaried_formality_tests.R` computes a two-sided test of equality of formal and
informal 101+/solo log contrasts and an eight-restriction joint Wald F test of
equality of the solo-based size profiles. It uses the full coefficient covariance,
with both sector-department and sector clustering. The salaried script calls it
automatically. To rerun these tests without refitting the regressions, run
`Rscript --vanilla replication/salaried_formality_tests.R` after generating
the local aggregate-model cache. Results are committed in
`salaried_output/formality_equality_tests.csv`.
The Python validator independently tests the eight interaction coefficients
in the fitted reference category, rather than R's solo-based contrast matrix,
and verifies the displayed p-values. Among salaried workers, the baseline
101+/solo equality test has p = 0.897, but the joint profile test has p < 0.001.
Failing to reject the former is not proof that the two premiums are identical.

The accompanying figure plots the salaried-only model's contrasts relative to
solo employees within each formality group, using sector-department-clustered
95 percent confidence intervals. `plot_salaried_robustness.R` generates English
and Spanish PNGs in `Paper/figures` without refitting any regression. It preserves
the full-sample preferred figure's category order, styling, and vertical scale.
The plotted estimates, bounds, labels, and axis limits are recorded in
`salaried_output/figure_profiles.csv` and checked against the regression outputs
by the validator. Both figures remain in the main text.

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

## Clustering and Wild Bootstrap Audit

The appendix comparison is generated from `inference_audit_output/`. It holds
the preferred model, joint endpoint model, and interacted elasticity model
fixed while comparing sector-department intersections, sector, department,
and two-way sector and department clustering. The wild cluster bootstrap
uses `fwildclusterboot` 0.14.3, WCR11 with the null imposed, Rademacher weights,
9,999 draws, and seed 20261018. Two-way studentization draws bootstrap weights
by sector, the dimension with fewer clusters.

The two appendix tables can be rebuilt from the committed aggregate outputs
without microdata:

```sh
python replication/build_inference_tables.py
```

To rerun the audit, follow the commands and dependency information in
`inference_audit_output/README.md`. `inference_audit_prepare.py` reads the model
file from the sibling CJC-Monitor checkout and accumulates weighted within-cell
cross-products in bounded-memory chunks. `inference_audit_bootstrap.R` uses
their square-root representation with the established bootstrap package.
`validate_inference_compression.R` independently verifies equivalence to
individual WLS with explicit fixed effects on synthetic test data.
`inference_audit_validate.py` checks the original empirical results and
records the survey-design identifiers available in local source metadata.

The full comparison contains 45 contrasts, with 180 conventional tests and
135 bootstrap tests. The appendix displays 19 contrasts. No bootstrap
confidence intervals or multiple-testing adjustments are claimed. The formal
endpoint change with two-way studentization loses 209 invalid draws. This is
flagged in the table and raw output rather than treated as a complete run.

The main tables retain their stated baseline covariance convention. The text
now distinguishes the robust informal premium and formal 101+ advantages over
non-solo categories from the sensitive formal 101+/solo and informal endpoint
tests. This audit does not reconstruct the exact GEIH sampling variance,
because the model file lacks the required design identifiers.

`build/inference_audit/` contains private computational caches and is excluded
from Git. Only aggregate tests, verification results, and source variable
metadata are published. The previously displayed two-convention extension
table remains available in its source file but is superseded in the PDF by
the expanded comparison and bootstrap tables.

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

The R script first verifies its eight informal and eight formal size coefficients and their standard errors against column (4) in `Paper/tables/regression_local_geography_formality_robustness.csv`. The preferred estimation sample has 5,268,375 observations and 559 sector-department clusters. The 2025 simulation sample has 341,282 observations. The Python step independently reconstructs all six unrestricted scenarios for both baselines and all three denominators (all workers, the target group, and reassigned workers) from the 18 size-formality groups.

## Interpretation

- Baseline hourly income is exponentiated fitted log income times a common survey-weighted smearing factor, computed from 2025 residuals. The factor cancels from percentage changes. This assumes a common exponential residual moment, not a destination-specific residual distribution.
- Each worker receives the estimated destination-to-origin wage multiplier. Weekly income is hourly income times unchanged weekly hours. Aggregate changes use weighted sums of weekly income, not means of individual percentage gains.
- Target-group denominators include members already in the destination. All-worker denominators include the entire 2025 sample. Expansion-weight sums are not reported as counts of unique annual workers.
- Reassigned-worker denominators (`population = movers`) exclude workers whose size and formality do not change. Their percentage changes in total and mean predicted weekly income coincide because the population and weights remain fixed. The introduction reports 41.9 percent for informal-to-formal reassignment at the same size, 13.7 percent for formal moves to 101+, and 24.2 percent for informal moves to 101+. These are changes in mean income, not means of individual percentage changes.
- The observed-baseline sensitivity preserves each worker's log residual and multiplies observed income by the same conditional wage ratio.
- The maximum-profile scenarios select 101+ for formal workers and 51--100 for informal workers. These destinations are common within each group under the additive model, not worker-specific comparative advantages. They are selected from estimated coefficients.
- Support screens count destination observations by sector, department, occupational position, size, and formality. Workers who fail a screen remain at origin. Smaller totals then partly reflect fewer moves, not new regression estimates. No eligible moves is distinct from a zero estimated return.
- The extra intervals saved in `scenario_results.csv` propagate only contrast-coefficient uncertainty, holding baseline income predictions, composition, hours, weights, and destinations fixed. They are not full sampling intervals and are not reported in the manuscript tables. Maximum-profile frequencies are coefficient-draw frequencies, not probabilities of policy optimality.
- These are conditional income scenarios. They do not estimate causal effects, equilibrium reallocations, output gains, productivity losses, or welfare.

## Data Handling

`private_cache/` contains working observations and must not be published. Detailed destination-cell counts, occupational-position cell counts, and local metadata are also excluded from version control. The committed outputs contain aggregate scenario results and validation checks only.

The manuscript reference model was at commit `081a61eb090da23b4927168863bef7286c15667c` when this exercise was verified. R 4.5.2 was used. Package versions and the input size, modification time, and reference-table hash are recorded in the local run metadata and cache signature.
