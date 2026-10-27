"""Check occupational recoding, sample accounting, and full-covariance contrasts."""
import csv
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/salaried_output"
sys.path.insert(0, str(ROOT / "build/qa_dependencies"))
import numpy as np
from scipy.stats import t, f


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


models = {r["sample"]: r for r in read("models")}
coefs = {s: {r["term"]: float(r["estimate"]) for r in read("coefficients") if r["sample"] == s}
         for s in models}
covariance = {s: {(r["clustering"], r["term1"], r["term2"]): float(r["covariance"])
                  for r in read("covariance_"+s)} for s in models}


def profile(sample, size, group):
    if size == models[sample]["base"]:
        return {}
    name = "tamano_empresa::"+size
    result = {name: 1}
    if group == "Formal":
        choices = {name+":formal", "formal:"+name}.intersection(coefs[sample])
        assert len(choices) == 1
        result[choices.pop()] = 1
    return result


contrasts = read("contrasts")
assert len(contrasts) == 2*3*8*2*2
for row in contrasts:
    sample, clustering = row["sample"], row["clustering"]
    a, b = profile(sample, row["size"], row["group"]), profile(sample, row["reference"], row["group"])
    z = {k: a.get(k, 0)-b.get(k, 0) for k in set(a) | set(b)}
    estimate = sum(v*coefs[sample][k] for k, v in z.items())
    var = sum(va*vb*covariance[sample][clustering, ka, kb] for ka, va in z.items() for kb, vb in z.items())
    se = math.sqrt(var)
    df = float(models[sample]["df_sector" if clustering == "Sector" else "df"])
    assert abs(estimate-float(row["estimate"])) < 1e-10
    assert abs(se-float(row["std.error"])) < 1e-10
    assert abs(2*t.sf(abs(estimate/se), df)-float(row["p.value"])) < 1e-10
    assert abs(100*math.expm1(estimate)-float(row["premium"])) < 1e-8
    for side, sign in (("low", -1), ("high", 1)):
        assert abs(100*math.expm1(estimate+sign*t.ppf(.975, df)*se)-float(row["ci_"+side])) < 1e-7

for sample, model in models.items():
    names = list(coefs[sample])
    for clustering in ("Sector", "Sector-department"):
        V = np.array([[covariance[sample][clustering, a, b] for b in names] for a in names])
        assert np.max(np.abs(V-V.T)) < 1e-12
        assert np.linalg.eigvalsh(V).min() > -1e-8
    assert sum(int(r["observations"]) for r in read("sample_counts") if r["sample"] == sample) == int(model["n"])
audit = read("sample_audit")[0]
assert int(audit["full_sample"]) == int(models["All"]["n"]) == 5426174
assert int(audit["salaried_candidates"])-int(audit["additional_singletons_removed"]) == int(models["Salaried"]["n"])
for row in read("occupation_audit"):
    year, raw, code = (int(row[x]) for x in ("anio", "occupation_raw_code", "occupation_harmonized_code"))
    expected = raw  # Corrected input codes are already aligned across questionnaires.
    assert code == expected
    assert (row["wage_employee"] == "TRUE") == (code in (1, 2, 3, 8))
assert sum(int(r["observations"]) for r in read("occupation_audit")) == 5426316
for row in read("reference_invariance_check"):
    assert max(abs(float(row[k])) for k in ("coef_error", "se_error")) < 1e-7
# The old occupation-only audit used the previous income/sample definition.
# Current reference invariance is checked above on the corrected sample.

tests = read("formality_equality_tests")
assert len(tests) == 8
for row in tests:
    sample, clustering = row["sample"], row["clustering"]
    names = list(coefs[sample])
    b = np.array([coefs[sample][name] for name in names])
    V = np.array([[covariance[sample][clustering, a, c] for c in names] for a in names])
    df = float(models[sample]["df_sector" if clustering == "Sector" else "df"])
    assert float(row["df_den"]) == df
    if row["test"] == "101+/solo equality":
        parts = [(profile(sample, "101+", "Formal"), 1), (profile(sample, "Solo", "Formal"), -1),
                 (profile(sample, "101+", "Informal"), -1), (profile(sample, "Solo", "Informal"), 1)]
        z = np.array([sum(sign*p.get(name, 0) for p, sign in parts) for name in names])
        estimate, se = float(z@b), math.sqrt(float(z@V@z))
        assert abs(estimate-float(row["estimate"])) < 1e-10
        assert abs(se-float(row["std.error"])) < 1e-10
        statistic, p = estimate/se, 2*t.sf(abs(estimate/se), df)
    else:
        assert row["test"] == "Joint profile equality"
        # Test the eight interaction coefficients directly in the fitted base.
        # This is equivalent to R's eight differences of solo-based contrasts.
        indices = [i for i, name in enumerate(names) if "tamano_empresa::" in name
                   and (name.endswith(":formal") or name.startswith("formal:"))]
        assert len(indices) == int(row["df_num"]) == 8
        d = b[indices]
        C = V[np.ix_(indices, indices)]
        assert np.linalg.matrix_rank(C) == 8
        statistic = float(d@np.linalg.solve(C, d)/8)
        p = f.sf(statistic, 8, df)
    assert abs(statistic-float(row["statistic"])) < 1e-8
    assert abs(p-float(row["p.value"])) < 1e-10

# Check every displayed coefficient, star, and standard error against the CSV.
lookup = {(r["sample"], r["group"], r["size"]): r for r in contrasts
          if r["reference"] == "11-19" and r["clustering"] == "Sector-department"}
text = (ROOT / "Paper/sections/regression_salaried_robustness_table.tex").read_text(encoding="utf-8")
lines = text.splitlines()
checked = 0
for i, line in enumerate(lines):
    cells = [x.strip() for x in line.strip().removesuffix(r"\\").split(" & ")]
    size = cells[0].replace("--", "-")
    if ("All", "Informal", size) not in lookup:
        continue
    ses = [x.strip().strip("()") for x in lines[i+1].strip().removesuffix(r"\\").split("&")][1:]
    for (sample, group), cell, se in zip([(s, g) for s in models for g in ("Informal", "Formal")], cells[1:], ses):
        row = lookup[sample, group, size]
        p = float(row["p.value"])
        stars = "***" if p < .01 else "**" if p < .05 else "*" if p < .1 else ""
        assert cell == f'{float(row["estimate"]):.3f}{stars}'
        assert abs(float(se)-float(row["std.error"])) <= .000501
        checked += 1
assert checked == 32
for size in ("11-19", "101+"):
    summary = next(line for line in lines if size.replace("-", "--")+"/solo premium" in line)
    displayed = [float(x.strip()) for x in summary.strip().removesuffix(r"\\").split("&")[1:]]
    for (sample, group), value in zip([(s, g) for s in models for g in ("Informal", "Formal")], displayed):
        row = next(r for r in contrasts if r["sample"] == sample and r["group"] == group and r["size"] == size
                   and r["reference"] == "Solo" and r["clustering"] == "Sector-department")
        assert abs(value-float(row["premium"])) < .05001
for label, test in [("Equal 101+/solo premiums", "101+/solo equality"), ("Equal size profiles", "Joint profile equality")]:
    line = next(line for line in lines if label in line)
    cells = re.findall(r"\\multicolumn\{2\}\{c\}\{([^}]+)\}", line)
    assert len(cells) == 2
    for sample, cell in zip(("All", "Salaried"), cells):
        p = float(next(r for r in tests if r["sample"] == sample and r["test"] == test
                       and r["clustering"] == "Sector-department")["p.value"])
        assert cell == ("$<0.001$" if p < .001 else f"{p:.3f}")
results = (ROOT / "Paper/sections/results.tex").read_text(encoding="utf-8")
table_input = r"\input{Paper/sections/regression_salaried_robustness_table}"
assert results.count(table_input) == 1
# Check section membership rather than a fixed order of subsections.
salaried_section = results.split(r"\subsection{Salaried Workers}", 1)[1]
salaried_section = salaried_section.split(r"\subsection{", 1)[0]
assert table_input in salaried_section
assert table_input not in (ROOT / "Paper/sections/comparison_results_appendix.tex").read_text(encoding="utf-8")

# Verify all plotted values and the common vertical scale against the source CSVs.
plot_rows = read("figure_profiles")
assert len(plot_rows) == len({(r["group"], r["size"]) for r in plot_rows}) == 16
solo_rows = {(r["group"], r["size"]): r for r in contrasts if r["sample"] == "Salaried"
             and r["reference"] == "Solo" and r["clustering"] == "Sector-department"}
with (ROOT / "replication/preferred_output/profiles.csv").open(encoding="utf-8-sig", newline="") as stream:
    full = [r for r in csv.DictReader(stream) if r["reference"] == "Solo"]
bounds = [0] + [float(r[k]) for r in full for k in ("ci_low", "ci_high")]
bounds += [max(float(r["ci_high"])+2.5, 4) for r in full]
low, high = min(bounds), max(bounds)
for row in plot_rows:
    source = solo_rows[row["group"], row["size"]]
    for key in ("estimate", "std.error", "premium", "ci_low", "ci_high", "p.value", "df"):
        assert abs(float(row[key])-float(source[key])) < 1e-10
    assert row["label"] == f'{float(source["premium"]):.1f}%'
    assert (row["significant"] == "TRUE") == (float(source["p.value"]) < .05)
    assert abs(float(row["axis_min"])-(low-.07*(high-low))) < 1e-9
    assert abs(float(row["axis_max"])-(high+.14*(high-low))) < 1e-9
    assert float(row["axis_min"]) <= float(row["ci_low"]) <= float(row["ci_high"]) <= float(row["axis_max"])
from PIL import Image
for lang in ("en", "es"):
    with Image.open(ROOT / f"Paper/figures/salaried_formality_premiums_{lang}.png") as picture:
        assert picture.size == (3600, 1800)
assert results.count(r"\label{fig:salaried-formality-premium}") == 1
assert r"Figure~\ref{fig:salaried-formality-premium}" in results
print(f"PASS: {len(contrasts)} full-covariance contrasts, {checked} table coefficients, eight equality tests, 16 plotted estimates and intervals, common figure scale, sample accounting, and main-text placement.")
