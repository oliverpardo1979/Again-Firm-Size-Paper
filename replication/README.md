# Regression Replication and Income Counterfactuals

## Synchronized Regression Outputs

The manuscript's regression tables and figures are generated from one estimation
run, using the same harmonized input file. The three reference categories are
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
code. Its size-and-modification-time signature automatically invalidates it when
the input data file changes.

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
