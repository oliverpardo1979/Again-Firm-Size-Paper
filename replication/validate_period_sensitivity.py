"""Independently validate the four-fit period sensitivity and compare the baseline.

Writes only aggregate comparisons and validation receipts in period_sensitivity_output.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import platform
import sys

ROOT = Path(__file__).resolve().parents[1]
if importlib.util.find_spec("scipy") is None:
    sys.path.insert(0, str(ROOT / "build/qa_dependencies"))

import numpy as np
import pandas as pd
import scipy
from scipy.stats import t

OUT = ROOT / "replication/period_sensitivity_output"
YEARS = list(range(2010, 2020)) + list(range(2021, 2026))
SIZES = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]
CLUSTERS = ["Sector-department", "Sector"]
SCENARIOS = ["formalize_same_size", "formal_to_101", "informal_to_101", "combined_formal_101"]
EXPECTED = {
    "All": (4839346, 4839217, 653437, 341056),
    "Salaried": (2476870, 2476733, 335655, 185827),
}
checked = 0


def read(name, directory=OUT):
    return pd.read_csv(directory / (name + ".csv"))


def close(actual, expected, label, atol=1e-7, rtol=1e-10):
    global checked
    actual, expected = np.asarray(actual, dtype=float), np.asarray(expected, dtype=float)
    assert actual.shape == expected.shape, (label, actual.shape, expected.shape)
    assert np.isfinite(actual).all() and np.isfinite(expected).all(), label
    assert np.allclose(actual, expected, atol=atol, rtol=rtol), (
        label, float(np.max(np.abs(actual - expected)))
    )
    checked += actual.size


def same_rows(left, right, keys, columns, label):
    assert not left.duplicated(keys).any(), label
    assert not right.duplicated(keys).any(), label
    joined = left.merge(right, on=keys, how="outer", suffixes=("_new", "_old"),
                        validate="one_to_one", indicator=True)
    assert joined._merge.eq("both").all(), label
    for column in columns:
        close(joined[column + "_new"], joined[column + "_old"], label + " " + column)
    return joined


def md5(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "md5").hexdigest()


metadata = read("run_metadata").set_index("field").value
assert metadata["status"] == "complete"
assert metadata["input_definition"] == "primary-income-2026-10-21"
assert metadata["years"] == ",".join(map(str, YEARS))
assert int(metadata["threads"]) == 2
assert metadata["script_md5"] == md5(ROOT / "replication/period_sensitivity.R")
assert metadata["harmonization_md5"] == md5(ROOT / "replication/harmonize_occupation.R")
for row in read("baseline_manifest").itertuples(index=False):
    assert md5(ROOT / row.file) == row.md5, ("Baseline changed", row.file)

models = read("models").set_index("model")
assert set(models.index) == {f"{s.lower()}_{kind}" for s in EXPECTED for kind in ("pooled", "endpoints")}
assert models.warnings.fillna("").eq("").all(), models.warnings.dropna().tolist()
for sample, counts in EXPECTED.items():
    close(models.loc[f"{sample.lower()}_pooled", "n"], counts[1], "Pooled N", atol=0, rtol=0)
    close(models.loc[f"{sample.lower()}_endpoints", "n"], counts[2], "Endpoint N", atol=0, rtol=0)
for row in models.itertuples():
    assert "ref = 'Solo'" in row.formula and "sector_depto_year" in row.formula
    assert "i(posicion_ocupacional_label)" in row.formula
    assert ("* post" in row.formula) == row.Index.endswith("endpoints")
    close(row.df, row.clusters - 1, "Cluster df", atol=0, rtol=0)
    close(row.df_sector, row.sector_clusters - 1, "Sector df", atol=0, rtol=0)

coefs = read("coefficients")
cov = read("covariances")
assert not coefs.duplicated(["model", "term"]).any()
assert not cov.duplicated(["model", "clustering", "term1", "term2"]).any()
fits = {}
for name in models.index:
    b = coefs.loc[coefs.model.eq(name)].set_index("term").estimate
    matrices = {}
    for cl in CLUSTERS:
        part = cov.loc[cov.model.eq(name) & cov.clustering.eq(cl)]
        assert len(part) == len(b) ** 2
        v = part.pivot(index="term1", columns="term2", values="covariance").loc[b.index, b.index].to_numpy()
        close(v, v.T, "Symmetric covariance", atol=1e-12)
        assert np.linalg.eigvalsh(v).min() > -1e-8, (name, cl)
        matrices[cl] = v
    fits[name] = (b, matrices)


def unit(b, *candidates):
    found = [term for term in candidates if term in b.index]
    assert len(found) == 1, candidates
    z = np.zeros(len(b))
    z[b.index.get_loc(found[0])] = 1
    return z


def profile(b, size, formal, post=False):
    if size == "Solo":
        return np.zeros(len(b))
    term = "tamano_empresa::" + size
    z = unit(b, term)
    if formal:
        z += unit(b, term + ":formal", "formal:" + term)
    if post:
        z += unit(b, term + ":post", "post:" + term)
        if formal:
            z += unit(b, term + ":formal:post", "formal:" + term + ":post",
                      term + ":post:formal", "post:" + term + ":formal",
                      "formal:post:" + term, "post:formal:" + term)
    return z


def verify_contrast(row, name, z):
    b, matrices = fits[name]
    estimate = z @ b.to_numpy()
    variance = z @ matrices[row["clustering"]] @ z
    assert variance > 0
    se = np.sqrt(variance)
    df = models.loc[name, "df" if row["clustering"] == "Sector-department" else "df_sector"]
    critical = t.ppf(.975, df)
    expected = {"estimate": estimate, "std.error": se, "p.value": 2*t.sf(abs(estimate/se), df),
                "conf.low": estimate-critical*se, "conf.high": estimate+critical*se,
                "premium": 100*np.expm1(estimate), "ci_low": 100*np.expm1(estimate-critical*se),
                "ci_high": 100*np.expm1(estimate+critical*se), "df": df}
    for field, value in expected.items():
        close(row[field], value, name + " " + field)


profiles = read("pooled_profiles")
gaps = read("formal_informal_gaps")
endpoints = read("endpoint_changes")
levels = read("endpoint_levels")
assert (len(profiles), len(gaps), len(endpoints), len(levels)) == (64, 36, 64, 128)
for frame in (profiles, endpoints):
    assert not frame.duplicated(["sample", "size", "group", "clustering"]).any()
    assert set(frame.reference) == {"Solo"}
    assert set(frame.clustering) == set(CLUSTERS)
for row in profiles.to_dict("records"):
    name = row["sample"].lower() + "_pooled"
    verify_contrast(row, name, profile(fits[name][0], row["size"], row["group"] == "Formal"))
for row in gaps.to_dict("records"):
    name = row["sample"].lower() + "_pooled"
    b = fits[name][0]
    verify_contrast(row, name, unit(b, "formal") + profile(b, row["size"], True) - profile(b, row["size"], False))
for row in levels.to_dict("records"):
    name = row["sample"].lower() + "_endpoints"
    verify_contrast(row, name, profile(fits[name][0], row["size"], row["group"] == "Formal", row["year"] == 2025))
for row in endpoints.to_dict("records"):
    name = row["sample"].lower() + "_endpoints"
    b = fits[name][0]
    early = profile(b, row["size"], row["group"] == "Formal")
    late = profile(b, row["size"], row["group"] == "Formal", True)
    verify_contrast(row, name, late-early)
    p0, p1 = 100*np.expm1(early @ b), 100*np.expm1(late @ b)
    close([row["premium_2010"], row["premium_2025"], row["change_pp"]], [p0, p1, p1-p0], "Endpoint percentages")


def endpoint_test(name, z, cl):
    b, matrices = fits[name]
    estimate = z @ b.to_numpy()
    se = np.sqrt(z @ matrices[cl] @ z)
    df = models.loc[name, "df" if cl == "Sector-department" else "df_sector"]
    statistic, critical = estimate/se, t.ppf(.975, df)
    return {"estimate": estimate, "std.error": se, "t_statistic": statistic, "df": df,
            "critical_t_975": critical, "p.value": 2*t.sf(abs(statistic), df),
            "conf.low": estimate-critical*se, "conf.high": estimate+critical*se,
            "significant_5pct": bool(abs(statistic) > critical)}


precision_rows, difference_rows = [], []
for sample in EXPECTED:
    name = sample.lower() + "_endpoints"
    b = fits[name][0]
    i0, f0 = profile(b, "101+", False), profile(b, "101+", True)
    i1, f1 = profile(b, "101+", False, True), profile(b, "101+", True, True)
    for cl in CLUSTERS:
        for group, z in (("Informal", i1-i0), ("Formal", f1-f0)):
            precision_rows.append({"sample": sample, "group": group, "clustering": cl,
                                   **endpoint_test(name, z, cl)})
        for period, z in (("2010", i0-f0), ("2025", i1-f1), ("Change", (i1-i0)-(f1-f0))):
            difference_rows.append({"sample": sample, "period": period,
                                    "comparison": "Informal minus formal, 101+/Solo log premium",
                                    "clustering": cl, **endpoint_test(name, z, cl)})
precision = pd.DataFrame(precision_rows)
differences = pd.DataFrame(difference_rows)
cross_language = 0
for name, frame, keys in (
    ("endpoint_precision_R", precision, ["sample", "group", "clustering"]),
    ("dynamic_formality_tests_R", differences, ["sample", "period", "clustering"]),
):
    if (OUT / (name + ".csv")).exists():
        ref = read(name)
        if "period" in ref:
            ref["period"] = ref.period.astype(str)
        joined = frame.merge(ref, on=keys, how="outer", suffixes=("_py", "_R"),
                             indicator=True, validate="one_to_one")
        assert joined._merge.eq("both").all()
        for field in ("estimate", "std.error", "t_statistic", "df", "critical_t_975", "p.value",
                      "conf.low", "conf.high", "significant_5pct"):
            close(joined[field + "_py"], joined[field + "_R"], "R/Python precision " + field, atol=1e-12)
        cross_language += len(joined)
saved_annual_checks = 0
if (OUT / "annual_2010_saved_fit_checks.csv").exists():
    saved = read("annual_2010_saved_fit_checks")
    assert len(saved) == 32 and not saved.duplicated(["sample", "size", "group"]).any()
    fields = ["coefficient_csv_error", "se_csv_error", "p_csv_error", "joint_coefficient_error"]
    close(saved[fields].to_numpy(), np.zeros((32, 4)), "Saved 2010 fits", atol=1e-7, rtol=0)
    saved_annual_checks = len(saved)

baseline = ROOT / "replication/salaried_extensions_output"
annual = read("annual_profiles_reused")
old_annual = read("annual_profiles", baseline)
old_annual = old_annual.loc[old_annual.reference.eq("Solo") & old_annual.year.isin(YEARS)]
assert len(annual) == 480
same_rows(annual, old_annual, ["sample", "year", "reference", "size", "group"],
          ["estimate", "std.error", "p.value", "premium", "ci_low", "ci_high", "df"], "Annual reuse")
same_rows(levels.loc[levels.clustering.eq("Sector-department")], annual.loc[annual.year.isin([2010, 2025])],
          ["sample", "year", "reference", "size", "group"], ["estimate", "premium"], "Joint/separate annual coefficients")

audit = read("sample_audit").set_index("sample")
old_audit = read("sample_audit", baseline).set_index("sample")
for sample, counts in EXPECTED.items():
    r = audit.loc[sample]
    close(r[["complete_observations", "pooled_observations", "observations_2025"]],
          [counts[0], counts[1], counts[3]], "Sample counts", atol=0, rtol=0)
    close(r.singletons_removed, counts[0]-counts[1], "Singletons", atol=0, rtol=0)
    fields = ["observations_2025", "workers_2025", "formal_workers_2025", "informal_workers_2025", "weighted_weekly_hours_2025"]
    close(r[fields], old_audit.loc[sample, fields], "Unchanged target population")
    close(r.workers_2025, r.formal_workers_2025+r.informal_workers_2025, "Population partition")
monthly = read("monthly_sample_counts")
assert len(monthly) == 360 and not monthly.duplicated(["sample", "anio", "MES"]).any()
for sample, counts in EXPECTED.items():
    q = monthly.loc[monthly["sample"].eq(sample)]
    assert set(zip(q.anio, q.MES)) == {(y, m) for y in YEARS for m in range(1, 13)}
    assert (q[["n", "workers"]] > 0).all().all()
    close(q.n.sum(), counts[1], "Monthly sample sum", atol=0, rtol=0)
    close(q.loc[q.anio.eq(2025), "workers"].sum(), audit.loc[sample, "workers_2025"], "Monthly worker weights")
    source = read("models", ROOT / ("replication/preferred_output" if sample == "All" else "replication/salaried_extensions_output"))
    for year in YEARS:
        name = ("year" if sample == "All" else "salaried_year") + str(year)
        close(q.loc[q.anio.eq(year), "n"].sum(), source.loc[source.model.eq(name), "n"].item(),
              "Annual sample consistency", atol=0, rtol=0)

income_profiles = read("pooled_income_profiles")
scenarios = read("income_scenarios")
origins = read("income_origin_aggregates")
assert len(income_profiles) == 54 and len(scenarios) == 36
assert set(scenarios.scenario) == set(SCENARIOS)
assert set(scenarios.support) == {"unrestricted"} and set(scenarios.method) == {"predicted"}
assert set(scenarios.metric) == {"weekly"}
scenario_keys = ["sample", "scenario", "support", "method", "metric", "population"]
assert not scenarios.duplicated(scenario_keys).any()
assert not origins.duplicated(["sample", "scenario", "origin", "dest"]).any()
for row in income_profiles.itertuples(index=False):
    name = "salaried_pooled" if row.sample == "Salaried" else "all_pooled"
    b = fits[name][0]
    z = profile(b, row.size, row.formal)
    if row.formal:
        z += unit(b, "formal")
    close(row.log_profile, z @ b, "Income profile")
    assert row.profile == SIZES.index(row.size)+1+9*row.formal
for row in scenarios.to_dict("records"):
    sample, scenario, population = (row[k] for k in ("sample", "scenario", "population"))
    a = origins.loc[origins["sample"].eq(sample) & origins.scenario.eq(scenario)].copy()
    lp = income_profiles.loc[income_profiles["sample"].eq(sample)].set_index("profile").log_profile
    delta = a.dest.map(lp)-a.origin.map(lp)
    close(a.delta_log, delta, "Origin/destination coefficients")
    origin, dest = a.origin.to_numpy(), a.dest.to_numpy()
    intended = {"formalize_same_size": np.where(origin <= 9, origin+9, origin),
                "formal_to_101": np.where(origin > 9, 18, origin),
                "informal_to_101": np.where(origin <= 9, 9, origin),
                "combined_formal_101": np.full(len(origin), 18)}[scenario]
    close(dest, intended, "Scenario mapping", atol=0, rtol=0)
    moved = origin != dest
    close(delta.to_numpy()[~moved], np.zeros((~moved).sum()), "Unchanged nonmovers")
    group = {"formalize_same_size": origin <= 9, "informal_to_101": origin <= 9,
             "formal_to_101": origin > 9, "combined_formal_101": np.ones(len(origin), dtype=bool)}[scenario]
    sel = {"all": np.ones(len(origin), dtype=bool), "movers": moved, "target_group": group}[population]
    mass, weights = a.baseline_mass.to_numpy(), a.workers.to_numpy()
    assert (mass > 0).all() and (weights > 0).all()
    denominator = mass[sel].sum()
    numerator = (mass[sel]*np.exp(delta.to_numpy()[sel])).sum()
    values = {"gain_pct": 100*(numerator/denominator-1), "workers_total": weights.sum(),
              "workers_moved": weights[moved].sum(), "denominator_workers": weights[sel].sum(),
              "baseline_mass": denominator, "counterfactual_mass": numerator,
              "baseline_mean": denominator/weights[sel].sum(), "counterfactual_mean": numerator/weights[sel].sum(),
              "moved_worker_share_pct": 100*weights[moved].sum()/weights.sum(),
              "baseline_mover_income_share_pct": 100*mass[moved].sum()/mass.sum(),
              "workers_with_lower_predictions_pct_of_movers":
                  100*weights[moved & (delta.to_numpy() < -1e-12)].sum()/weights[moved].sum()}
    for field, value in values.items():
        close(row[field], value, "Income arithmetic " + field)
    target_sample = "All" if sample == "All" else "Salaried"
    close(weights.sum(), audit.loc[target_sample, "workers_2025"], "Scenario population")
    close(a.observations.sum(), audit.loc[target_sample, "observations_2025"], "Scenario observations", atol=0, rtol=0)
for row in read("replication_checks").itertuples(index=False):
    assert abs(row.error) < row.tolerance, row.check

# Comparisons use the adopted 2008-based outputs, never refit or overwritten here.
pooled_old = read("contrasts", ROOT / "replication/salaried_output")
pooled_old = pooled_old.loc[pooled_old.reference.eq("Solo") & pooled_old.clustering.isin(CLUSTERS)]
key = ["sample", "reference", "size", "group", "clustering"]
pooled_comparison = profiles.merge(pooled_old[key + ["premium", "p.value", "estimate"]], on=key,
                                  validate="one_to_one", suffixes=("_2010_start", "_2008_start"))
assert len(pooled_comparison) == 64
pooled_comparison["premium_difference_pp"] = pooled_comparison.premium_2010_start-pooled_comparison.premium_2008_start
old_endpoints = read("endpoint_changes", baseline)
old_endpoints = old_endpoints.loc[old_endpoints.reference.eq("Solo") & old_endpoints.clustering.isin(CLUSTERS)]
endpoint_comparison = endpoints.merge(old_endpoints[key + ["premium_2008", "premium_2025", "change_pp", "p.value"]],
                                     on=key, validate="one_to_one", suffixes=("_2010_start", "_2008_start"))
assert len(endpoint_comparison) == 64
close(endpoint_comparison.premium_2025_2010_start, endpoint_comparison.premium_2025_2008_start,
      "Unchanged 2025 endpoint")
old_scenarios = read("income_scenarios", baseline)
old_scenarios = old_scenarios.loc[old_scenarios.support.eq("unrestricted") & old_scenarios.method.eq("predicted")
                                & old_scenarios.metric.eq("weekly")]
income_comparison = scenarios.merge(old_scenarios[scenario_keys + ["gain_pct", "workers_moved", "workers_total"]],
                                   on=scenario_keys, validate="one_to_one", suffixes=("_2010_start", "_2008_start"))
assert len(income_comparison) == 36
for field in ("workers_moved", "workers_total"):
    close(income_comparison[field + "_2010_start"], income_comparison[field + "_2008_start"], "Unchanged scenario population")
income_comparison["gain_difference_pp"] = income_comparison.gain_pct_2010_start-income_comparison.gain_pct_2008_start
pooled_comparison.to_csv(OUT / "pooled_baseline_comparison.csv", index=False)
endpoint_comparison.to_csv(OUT / "endpoint_baseline_comparison.csv", index=False)
income_comparison.to_csv(OUT / "income_baseline_comparison.csv", index=False)
precision.to_csv(OUT / "endpoint_precision.csv", index=False)
differences.to_csv(OUT / "dynamic_formality_tests.csv", index=False)
versions = {"python": platform.python_version(), "numpy": np.__version__, "pandas": pd.__version__, "scipy": scipy.__version__}
report = {"status": "passed", "numerical_comparisons": checked, "models": 4, "sample_months": 360,
          "annual_profiles_reused": 480, "pooled_profiles": 64, "formality_gaps": 36,
          "endpoint_levels": 128, "joint_endpoint_changes": 64, "income_scenarios": 36,
          "dynamic_formality_tests": 12, "saved_2010_fit_contrasts": saved_annual_checks,
          "R_Python_precision_contrasts": cross_language,
          "input_md5": metadata["input_md5"], "versions": versions,
          "scope": "Adopted processed input. No fresh raw reconstruction or bootstrap.",
          "endpoint_comparison": "2010/2025 versus 2008/2025 changes cover different intervals."}
(OUT / "validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
print("\nPooled 101+/Solo premiums")
print(pooled_comparison.loc[pooled_comparison["size"].eq("101+") & pooled_comparison.clustering.eq("Sector-department"),
      ["sample", "group", "premium_2008_start", "premium_2010_start", "premium_difference_pp"]].to_string(index=False))
print("\nJoint 2010/2025 endpoint changes")
print(endpoints.loc[endpoints["size"].eq("101+"),
      ["sample", "group", "clustering", "premium_2010", "premium_2025", "change_pp", "p.value"]].to_string(index=False))
print("\n2025 all-worker income gains")
print(income_comparison.loc[income_comparison["sample"].isin(EXPECTED) & income_comparison.population.eq("all"),
      ["sample", "scenario", "gain_pct_2008_start", "gain_pct_2010_start", "gain_difference_pp"]].to_string(index=False))
print("\nInformal-minus-formal difference in 2010/2025 log-premium changes")
print(differences.loc[differences.period.eq("Change"),
      ["sample", "clustering", "estimate", "std.error", "p.value"]].to_string(index=False, float_format=lambda v: f"{v:.12g}"))
