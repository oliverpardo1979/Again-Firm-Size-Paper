"""Independently validate exploratory results using aggregate exports only."""
import csv
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/salaried_extensions_output"
sys.path.insert(0, str(ROOT / "build/qa_dependencies"))
from scipy.stats import t


def read(name, directory=OUT):
    with (directory / (name + ".csv")).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


checked = 0


def close(actual, expected, label, tolerance=1e-8):
    global checked
    actual, expected = float(actual), float(expected)
    assert math.isfinite(actual) and math.isfinite(expected), label
    assert abs(actual - expected) <= tolerance, (label, actual, expected)
    checked += 1


coefs = defaultdict(dict)
for row in read("coefficients"):
    coefs[row["model"]][row["term"]] = float(row["estimate"])
cov = {
    (r["model"], r["clustering"], r["term1"], r["term2"]): float(r["covariance"])
    for r in read("endpoint_covariances")
}


def term_name(b, requested):
    tokens = sorted(requested.split(":"))
    matches = [k for k in b if sorted(k.split(":")) == tokens]
    assert len(matches) == 1, (requested, matches)
    return matches[0]


def profile(model, size, formal, post=False):
    if size == "Solo":
        return {}
    term = "tamano_empresa::" + size
    z = {term: 1}
    if formal:
        z[term + ":formal"] = 1
    if post:
        z[term + ":post"] = 1
        if formal:
            z[term + ":formal:post"] = 1
    return {term_name(coefs[model], k): v for k, v in z.items()}


def combine(*parts):
    result = defaultdict(float)
    for z, sign in parts:
        for term, weight in z.items():
            result[term] += sign * weight
    return {k: v for k, v in result.items() if v}


def dot(model, z):
    return sum(coefs[model][k] * v for k, v in z.items())


def validate_contrast(row, model, z):
    cl = row["clustering"]
    estimate = dot(model, z)
    variance = sum(a * b * cov[model, cl, i, j] for i, a in z.items() for j, b in z.items())
    assert variance > 0
    se = math.sqrt(variance)
    df = float(row["df"])
    close(row["estimate"], estimate, "contrast coefficient")
    close(row["std.error"], se, "contrast standard error")
    close(row["p.value"], 2 * t.sf(abs(estimate / se), df), "two-sided p")
    close(row["premium"], 100 * math.expm1(estimate), "exponentiated contrast")
    for side, sign in (("low", -1), ("high", 1)):
        close(row["ci_" + side], 100 * math.expm1(estimate + sign * t.ppf(.975, df) * se), "CI")


endpoints = read("endpoint_changes")
assert len(endpoints) == 256
for row in endpoints:
    model = row["sample"].lower() + "_endpoints"
    size, ref, formal = row["size"], row["reference"], row["group"] == "Formal"
    early = combine((profile(model, size, formal), 1), (profile(model, ref, formal), -1))
    late = combine((profile(model, size, formal, True), 1), (profile(model, ref, formal, True), -1))
    p0, p1 = (100 * math.expm1(dot(model, z)) for z in (early, late))
    close(row["premium_2008"], p0, "2008 premium")
    close(row["premium_2025"], p1, "2025 premium")
    close(row["change_pp"], p1 - p0, "premium change pp")
    validate_contrast(row, model, combine((late, 1), (early, -1)))

formality = read("dynamic_formality_tests")
assert len(formality) == 24
for row in formality:
    model = row["sample"].lower() + "_endpoints"
    early = combine((profile(model, "101+", False), 1), (profile(model, "101+", True), -1))
    late = combine((profile(model, "101+", False, True), 1), (profile(model, "101+", True, True), -1))
    z = {"2008": early, "2025": late, "Change": combine((late, 1), (early, -1))}[row["period"]]
    validate_contrast(row, model, z)

annual = read("annual_profiles")
assert len(annual) == 1088
assert len({tuple(r[k] for k in ("sample", "year", "reference", "size", "group")) for r in annual}) == 1088
old_dir = ROOT / "replication/preferred_output"
old_annual = {(r["year"], r["size"], r["group"]): r for r in read("annual_profiles", old_dir)}
old_endpoints = {(r["size"], r["group"]): r for r in read("endpoint_changes", old_dir)}
for row in annual:
    if row["sample"] == "All" and row["reference"] == "Solo":
        old = old_annual[row["year"], row["size"], row["group"]]
        for key in ("estimate", "std.error", "p.value", "premium", "ci_low", "ci_high", "df"):
            close(row[key], old[key], "full annual " + key)
    if row["sample"] == "Salaried":
        model = "salaried_year" + row["year"]
        z = combine((profile(model, row["size"], row["group"] == "Formal"), 1),
                    (profile(model, row["reference"], row["group"] == "Formal"), -1))
        close(row["estimate"], dot(model, z), "annual salaried coefficient")
for row in endpoints:
    if row["sample"] == "All" and row["reference"] == "Solo" and row["clustering"] == "Sector-department":
        old = old_endpoints[row["size"], row["group"]]
        for key in ("estimate", "std.error", "p.value", "premium_2008", "premium_2025"):
            close(row[key], old[key], "full endpoints " + key)
audited = {
    (r["contrast"], r["clustering"]): r
    for r in read("conventional", ROOT / "replication/inference_audit_output") if r["model"] == "endpoints"
}
for row in endpoints:
    if row["sample"] == "All" and row["reference"] == "Solo" and row["size"] == "101+":
        old = audited[row["group"] + " change 101+/solo 2008-2025", row["clustering"]]
        for new_key, old_key in (("estimate", "estimate"), ("std.error", "se"), ("p.value", "p"), ("df", "df")):
            close(row[new_key], old[old_key], "published clustering " + new_key)

scenarios = read("income_scenarios")
assert len(scenarios) == 288
keys = ("sample", "scenario", "support", "method", "metric")
grouped = defaultdict(list)
for row in read("income_origin_aggregates"):
    grouped[tuple(row[k] for k in keys)].append(row)
full_b = {r["term"]: float(r["estimate"]) for r in read("coefficients", old_dir) if r["model"] == "preferred"}
sizes = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]


def log_level(b, index):
    formal, size_index = divmod(index - 1, 9)
    value = formal * b["formal"]
    if size_index:
        term = "tamano_empresa::" + sizes[size_index]
        value += b[term] + formal * b[term_name(b, term + ":formal")]
    return value


for row in scenarios:
    cells = grouped[tuple(row[k] for k in keys)]
    b = coefs["salaried_pooled"] if row["sample"] == "Salaried" else full_b
    denominator = gain = movers_mass = mover_count = total_mass = workers = lower = 0.0
    for cell in cells:
        origin, dest = int(cell["origin"]), int(cell["dest"])
        mass, count = float(cell["baseline_mass"]), float(cell["workers"])
        delta = log_level(b, dest) - log_level(b, origin)
        close(delta, cell["delta_log"], "income reassignment coefficient")
        moved = origin != dest
        if row["support"] == "unrestricted":
            expected = {"formalize_same_size": origin + 9 if origin <= 9 else origin,
                        "formal_to_101": 18 if origin > 9 else origin,
                        "informal_to_101": 9 if origin <= 9 else origin,
                        "combined_formal_101": 18}[row["scenario"]]
            assert dest == expected
        target = {"formalize_same_size": origin <= 9, "informal_to_101": origin <= 9,
                  "formal_to_101": origin > 9, "combined_formal_101": True}[row["scenario"]]
        selected = {"all": True, "movers": moved, "target_group": target}[row["population"]]
        if selected:
            denominator += mass
            gain += mass * math.expm1(delta)
        workers += count
        total_mass += mass
        if moved:
            mover_count += count
            movers_mass += mass
            if delta < -1e-12:
                lower += count
    if denominator:
        close(row["gain_pct"], 100 * gain / denominator, "independent aggregate income gain")
    else:
        assert row["gain_pct"] == "NA" and row["population"] == "movers"
    close(row["workers_total"], workers, "expansion total", 1e-5)
    close(row["workers_moved"], mover_count, "expanded mover count", 1e-5)
    close(row["moved_worker_share_pct"], 100 * mover_count / workers, "mover share")
    close(row["baseline_mover_income_share_pct"], 100 * movers_mass / total_mass, "mover income share")
    if mover_count:
        close(row["workers_with_lower_predictions_pct_of_movers"], 100 * lower / mover_count, "loser share")

old_income = {
    tuple(r[k] for k in ("scenario", "support", "method", "metric", "population")): r
    for r in read("scenario_results", ROOT / "replication/output")
}
for row in scenarios:
    if row["sample"] != "All":
        continue
    old_method = "predicted_common_smear" if row["method"] == "predicted" else row["method"]
    key = (row["scenario"], row["support"], old_method, row["metric"], row["population"])
    if key not in old_income:
        assert (row["population"] == "movers" and float(row["workers_moved"]) == 0
                and row["gain_pct"] == "NA"), key
        continue
    old = old_income[key]
    if row["gain_pct"] != "NA":
        close(row["gain_pct"], old["gain_pct"], "published full income gain", 1e-7)
    close(row["moved_worker_share_pct"], old["moved_worker_share_pct"], "published full mover share")

for row in read("replication_checks"):
    assert abs(float(row["error"])) < float(row["tolerance"])
for row in read("sample_audit"):
    close(row["workers_2025"], float(row["formal_workers_2025"]) + float(row["informal_workers_2025"]), "sample partition", 1e-5)
    expected = {"All": (5268375, 341282), "Salaried": (2682009, 185829)}[row["sample"]]
    assert (int(row["pooled_observations"]), int(row["observations_2025"])) == expected

manuscript_checks = ""
if "--manuscript" in sys.argv:
    sections = ROOT / "Paper/sections"
    results = (sections / "results.tex").read_text(encoding="utf-8")
    subsection = results.split(r"\label{subsec:salaried-workers}", 1)[1].split(r"\subsection{Dynamic Results}", 1)[0]
    dynamic_text = (sections / "regression_salaried_dynamic_comparison_table.tex").read_text(encoding="utf-8")
    income_text = (sections / "income_salaried_comparison_table.tex").read_text(encoding="utf-8")
    dynamic_rows = [line for line in dynamic_text.splitlines() if " & Formal & " in line or " & Informal & " in line]
    assert len(dynamic_rows) == 4
    for line, (sample, group) in zip(dynamic_rows, [(s, g) for s in ("All", "Salaried") for g in ("Formal", "Informal")]):
        displayed = [float(x.strip()) for x in line.strip().removesuffix(r"\\").split("&")[2:]]
        source = next(r for r in endpoints if r["sample"] == sample and r["group"] == group
                      and r["reference"] == "Solo" and r["size"] == "101+" and r["clustering"] == "Sector-department")
        sector = next(r for r in endpoints if r["sample"] == sample and r["group"] == group
                      and r["reference"] == "Solo" and r["size"] == "101+" and r["clustering"] == "Sector")
        expected = [float(source[k]) for k in ("premium_2008", "premium_2025", "change_pp", "p.value")]
        expected.append(float(sector["p.value"]))
        for j, (value, raw) in enumerate(zip(displayed, expected)):
            close(value, raw, "displayed dynamic table", .050001 if j < 3 else .000501)
    income_rows = [line for line in income_text.splitlines() if " & " in line and " to " in line]
    assert len(income_rows) == 8
    scenario_order = ("formalize_same_size", "formal_to_101", "informal_to_101", "combined_formal_101")
    for line, (sample, scenario) in zip(income_rows, [(s, c) for s in ("All", "Salaried") for c in scenario_order]):
        displayed = [float(x.strip()) for x in line.strip().split(r"\\", 1)[0].split("&")[1:]]
        source = next(r for r in scenarios if r["sample"] == sample and r["scenario"] == scenario
                      and r["population"] == "all" and r["support"] == "unrestricted"
                      and r["method"] == "predicted" and r["metric"] == "weekly")
        movers = next(r for r in scenarios if r["sample"] == sample and r["scenario"] == scenario
                      and r["population"] == "movers" and r["support"] == "unrestricted"
                      and r["method"] == "predicted" and r["metric"] == "weekly")
        expected = [float(source["workers_moved"]) / 1e6, float(movers["gain_pct"]), float(source["gain_pct"])]
        for j, (value, raw) in enumerate(zip(displayed, expected)):
            close(value, raw, "displayed income table", .005001 if j == 0 else .050001)
    for stem, label in (("regression_salaried_dynamic_comparison_table", "salaried-dynamic-comparison"),
                        ("income_salaried_comparison_table", "salaried-income-comparison")):
        assert subsection.count(r"\input{Paper/sections/" + stem + "}") == 1
        assert r"\ref{tab:" + label + "}" in subsection
        assert r"\ref{tab:" + label + "}" in (sections / "discussion.tex").read_text(encoding="utf-8")
    assert r"\ref{eq:preferred-dynamics}" in dynamic_text
    assert r"\ref{eq:income-counterfactual}" in income_text
    assert r"\ref{eq:main}" in income_text
    plain = " ".join(subsection.split())
    for claim in ("20.3 percent in 2008", "39.1 percent in 2025", "18.8 percentage points",
                  "8.9 to 18.7 percent", r"p=0.038", r"p=0.094", r"p=0.404", r"p=0.027",
                  "12.71 million", "7.68 million", "25.6 percent", "11.9 percent", "12.6 percent",
                  "32.4 percent rather than 55.1 percent"):
        assert claim in plain, claim
    abstract = lambda name: re.search(r"\\begin\{abstract\}(.*?)\\end\{abstract\}",
                                     (ROOT / name).read_text(encoding="utf-8"), re.S).group(1)
    assert abstract("main.tex") == abstract("manuscript_no_author_details.tex")
    manuscript_checks = " Also checked both generated tables, equation references, subsection placement and numerical claims."

message = (
    f"PASS: {checked:,} numerical comparisons. Validated 256 endpoint contrasts, 24 dynamic "
    "formality tests, 1,088 annual profile rows and 288 scenario rows. Full-sample annual "
    "results, endpoint inference under four clustering choices, income gains and mover "
    "shares reproduce existing outputs. Income gains independently reconstructed from "
    "origin-destination aggregates and model coefficients. Empty supported mover groups "
    "are missing, not zero gains per mover."
    + manuscript_checks
)
(OUT / "validation.txt").write_text(message + "\n", encoding="utf-8")
print(message)
