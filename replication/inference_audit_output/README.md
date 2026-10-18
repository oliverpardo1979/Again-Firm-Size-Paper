# Clustered-inference audit

18 October 2026. Manuscript baseline c76f6f5. This audit was completed separately before author review. Its comparisons were subsequently incorporated into the appendix, with corresponding changes to inference statements in the manuscript. Coefficients and baseline covariance estimates remain unchanged.

## Main findings

The coefficients and estimation samples are unchanged. Inference is sensitive to allowing dependence across economic sectors within a department and across departments within an economic sector. Clustering on sector-department intersections does not allow either kind of cross-cell dependence.

- The formal 101+/solo premium is 16.49%. Its p-value is below 0.001 under the current intersection clustering, but 0.184 with sector wild bootstrap and 0.188 with two-way studentization.
- The informal 101+/solo premium is 37.13% and remains significant under every method examined. All eight informal size-versus-solo contrasts survive the bootstrap at 5%.
- Formal workers in 101+ firms earn more than formal workers in each of the seven categories from 2-3 through 51-100 workers. All seven comparisons remain significant at 5% with sector, department, and two-way bootstrap inference. These are pointwise tests, not a familywise multiple-testing procedure.
- The informal 101+/solo premium rises from 35.55% in 2008 to 57.74% in 2025, a difference of 22.19 percentage points. The null tested is equality of the corresponding log contrasts. Its p-value changes from 0.011 under intersection clustering to 0.111 with sector bootstrap, 0.266 with department bootstrap, and 0.273 with two-way studentization. The estimated widening is not robustly significant.
- The formal and informal size elasticities remain positive, at 0.0396 and 0.0966. The difference between them survives two-way bootstrap inference, p = 0.0015. This should not be confused with the difference between the two 101+/solo log contrasts, whose two-way bootstrap p-value is 0.0917.
- Formal-informal wage differences remain positive and significant within all nine size categories. The largest two-way bootstrap p-value among these nine comparisons is 0.0017.

## Conventional two-sided tests

All entries below are p-values. SD denotes one-way clustering on sector-department intersections. S+D denotes two-way clustering on sector and department separately, not their intersection.

| Contrast | SD | Sector | Department | S+D |
| --- | ---: | ---: | ---: | ---: |
| Formal 101+/solo | <0.001 | 0.113 | <0.001 | 0.090 |
| Informal 101+/solo | <0.001 | <0.001 | <0.001 | <0.001 |
| Formal 101+/11-19 | <0.001 | 0.002 | <0.001 | <0.001 |
| Informal change in 101+/solo, 2008-2025 | 0.011 | 0.090 | 0.124 | 0.199 |
| Formal elasticity | <0.001 | 0.003 | <0.001 | 0.002 |
| Informal elasticity | <0.001 | <0.001 | <0.001 | <0.001 |

## Wild cluster bootstrap

WCR11, null imposed, two-sided tests, Rademacher weights, 9,999 draws, seed 20261018. The S+D column uses two-way studentization and draws bootstrap weights by sector, the dimension with fewer clusters. The cluster finite-sample correction also uses the smaller cluster count. This is an explicit implementation choice, not a claim that it is the uniquely correct multiway bootstrap.

| Contrast | Sector | Department | S+D |
| --- | ---: | ---: | ---: |
| Formal 101+/solo | 0.184 | <0.001 | 0.188 |
| Informal 101+/solo | <0.001 | <0.001 | <0.001 |
| Formal 101+/11-19 | 0.004 | <0.001 | 0.003 |
| Informal change in 101+/solo, 2008-2025 | 0.111 | 0.266 | 0.273 |
| Formal elasticity | 0.016 | <0.001 | 0.017 |
| Informal elasticity | <0.001 | <0.001 | <0.001 |
| Formal-minus-informal elasticity | <0.001 | <0.001 | 0.002 |

Unrounded results appear in `comparison_all_contrasts.csv`. Zeros in the raw bootstrap CSV mean no simulated exceedances, not zero population probability. They are displayed here as <0.001. Monte Carlo uncertainty remains. At p near 0.19 or 0.27, its approximate standard error is 0.004-0.0045.

One additional test needs a numerical qualification. For the formal endpoint change under S+D, the package discarded 209 invalid bootstrap t-statistics and computed p = 0.933 from 9,790 retained draws. Its multiway studentization was undefined on those draws. This test should be flagged, not presented as a clean 9,999-draw result. Sector and department bootstrap p-values for the same contrast are 0.886 and 0.928, without discarded draws. None of the tests in the displayed tables discarded draws. All 134 other bootstrap runs retained 9,999 finite t-statistics.

## Formal large-firm comparisons

Each row compares formal 101+ employment with the indicated formal reference category.

| Reference | Premium (%) | Sector WCR p | S+D WCR p |
| --- | ---: | ---: | ---: |
| Solo | 16.49 | 0.184 | 0.188 |
| 2-3 | 25.19 | <0.001 | <0.001 |
| 4-5 | 19.09 | 0.002 | 0.002 |
| 6-10 | 15.00 | 0.003 | 0.004 |
| 11-19 | 11.98 | 0.004 | 0.003 |
| 20-30 | 12.03 | <0.001 | <0.001 |
| 31-50 | 9.77 | 0.006 | 0.004 |
| 51-100 | 6.98 | 0.024 | 0.017 |

## Sampling design and what remains unavailable

The DANE documentation describes probabilistic, stratified, multistage geographical sampling. The 2008 design includes forced-inclusion metropolitan units and successive geographical selections ending in segments of about ten dwellings. The redesigned GEIH describes municipalities as primary units and segments of approximately ten contiguous dwellings as secondary units. Everyone in the selected households is surveyed. The economic-sector categories used in the regressions are not these geographical sampling units. See [DANE 2008](https://microdatos.dane.gov.co/index.php/catalog/206/study-description) and [DANE 2025](https://microdatos.dane.gov.co/index.php/catalog/853/study-description).

The model file retains weights, department, area, and economic sector, but no explicit sampling-stratum, primary-unit, segment, or household identifiers. Its `persona_id` must not be treated as a survey-design identifier. The available construction code creates it with `gen long persona_id = _n`.

We also inspected 200 CSV headers in 14 locally available public archives covering 2021 and 2025. They contain keys such as DIRECTORIO, SECUENCIA_P, ORDEN, and HOGAR, but no explicitly named PSU, segment, or sampling-stratum fields in this inspection. Those keys cannot be assumed to identify sampling units without documentation. This is not a claim that no suitable design file can be obtained from DANE. Older raw files and any restricted design crosswalk were not exhaustively inspected.

Consequently, this audit does NOT estimate the exact survey-design variance. Recovering it requires documented design identifiers, including the treatment of forced-inclusion units and repeated sampling across periods. Applying survey weights does not by itself reconstruct that variance. The design assessment is therefore complete only as a diagnosis of what the current files support.

Department clustering allows dependence among sampled workers in the same department, including across sectors. Sector clustering allows dependence within an economic sector across departments. Two-way clustering permits both. Neither the number of fixed effects nor the smallest p-value determines which assumption is appropriate. Fixed effects can remove common means without removing all residual dependence. See [Cameron and Miller (2015)](https://cameron.econ.ucdavis.edu/research/Cameron_Miller_JHR_2015.pdf).

## Samples and methods

The preferred model uses 5,268,375 observations after removing 139 singleton sector-department-year cells. It includes firm-size indicators interacted with formality, sex, age, age squared, education indicators, occupational-position indicators, and sector-department-year fixed effects. The dependent variable is log real hourly labor income. The existing occupation-code correction and GEIH weights are retained.

The endpoint model uses 489,796 observations from 2008 and 2025. All slopes vary by endpoint, as in the existing paper exercise. Its joint covariance retains dependence across years within clusters. Elasticities use the existing assigned firm sizes and the interacted specification, not separate formal and informal regressions.

| Model | Observations | SD clusters | Sectors | Departments |
| --- | ---: | ---: | ---: | ---: |
| Preferred | 5,268,375 | 559 | 17 | 33 |
| Joint endpoints | 489,796 | 540 | 17 | 33 |
| Interacted elasticity | 5,268,375 | 559 | 17 | 33 |

Clusters are kept intact across years. One sector accounts for 21.24% of preferred-model observations. Seventeen uneven sectors warrant few-cluster checks despite the large individual sample.

Conventional covariance estimates use the original finite-N adjustment and G/(G-1). Multiway covariance uses sector plus department minus their intersection, with the minimum-cluster adjustment. Conventional tests use t critical values with G-1 degrees of freedom, or min(G)-1 for two-way clustering. No positive-semidefinite repair was imposed. All 45 observed scalar contrast variances were positive under all four covariance choices.

The bootstrap is implemented with `fwildclusterboot` 0.14.3. Its multiway and null-imposition options are documented in the [package reference](https://s3alfisc.github.io/fwildclusterboot/reference/boottest.fixest.html). Tests are pointwise. We have not produced bootstrap-inverted confidence intervals or adjusted for searching across many contrasts.

## Numerical validation

To respect available memory, weighted cell cross-products are accumulated directly from the microdata in chunks. Fixed effects are removed by exact weighted centering. A square-root representation preserves X'X and X'y in every sector-department cluster. Every bootstrap weighting group contains complete fixed-effect cells, so the WCR11 calculation can use this representation without changing the estimand. It is not a sampled subset of workers and is not a replacement dataset.

- Preferred coefficient replication error is below 4e-12.
- Original sector and sector-department covariance replication errors are below 9e-14.
- A further 99 checks reproduce existing premiums, endpoint tests, formality gaps, and elasticity tests within 2.1e-11.
- Bootstrap observed t-statistics agree with the original-microdata covariance calculation after its known finite-N scaling, within 1e-11.
- An independent synthetic-data test compares individual WLS with explicit fixed effects against the compressed calculation. Coefficients, observed t, p-values, and the full bootstrap t distributions agree within 2e-15 for sector, department, and two-way inference.

The common finite-N multiplier cancels from observed and bootstrap t-statistics, so it is omitted from bootstrap studentization. Age and age squared are internally scaled by 100 and 10,000 for numerical conditioning. The internal coefficient CSVs are not manuscript-ready regression tables.

## Interpretation and recommendation

Do not rely on sector-department intersections as the only reported inference. Two-way sector and department clustering, accompanied by a clearly specified wild-bootstrap sensitivity analysis, is a defensible working choice given plausible sectoral and geographical dependence. This recommendation has medium confidence because the exact survey-design variance remains unavailable and multiway inference still relies on assumptions with only 17 sectors.

The numerical comparison has high confidence after independent replication. It supports retaining the informal size premium, formal 101+ advantages over intermediate categories, and larger informal elasticity. It does not support describing the formal 101+/solo contrast or the informal increase over time as robustly significant. The subsequent manuscript revision reports these checks in the appendix without silently replacing the baseline inference convention.

## Files and reproduction

- `comparison_all_contrasts.csv` contains all 45 contrasts and every p-value comparison.
- `conventional.csv` contains estimates, standard errors, p-values, and log-scale confidence intervals for four covariance choices.
- `wild_bootstrap.csv` contains 135 bootstrap results, seeds, effective draw counts, and warnings.
- `cluster_sizes.csv` records cluster counts and sizes. `size_effective_G` is only an inverse size-concentration index, not inferential degrees of freedom.
- `model_data_metadata.json` and `public_raw_headers.json` record variable availability, not individual data.
- `replication_checks.csv`, `existing_results_validation.csv`, `bootstrap_validation.csv`, and `compression_bootstrap_validation.csv` record validation results.
- `bootstrap_provenance.txt` records the R environment.

Run from the repository root, with pandas, NumPy, SciPy, R, and the R dependencies recorded in the provenance file available:

```text
python replication/inference_audit_prepare.py
Rscript replication/inference_audit_bootstrap.R
Rscript replication/validate_inference_compression.R
python replication/inference_audit_validate.py
python replication/build_inference_tables.py
```

The source microdata are not redistributed. Private numerical caches and locally installed dependencies remain in the ignored `build/` directory.
