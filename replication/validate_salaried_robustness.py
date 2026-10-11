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
from scipy.stats import t


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
assert int(audit["full_sample"]) == int(models["All"]["n"]) == 5268375
assert int(audit["salaried_candidates"])-int(audit["additional_singletons_removed"]) == int(models["Salaried"]["n"])
for row in read("occupation_audit"):
    year, raw, code = (int(row[x]) for x in ("anio", "occupation_raw_code", "occupation_harmonized_code"))
    expected = {7: 8, 8: 9}.get(raw, raw) if year >= 2021 else raw
    assert code == expected
    assert (row["wage_employee"] == "TRUE") == (code in (1, 2, 3, 8))
assert sum(int(r["observations"]) for r in read("occupation_audit")) == 5268514
for row in read("reference_invariance_check"):
    assert max(abs(float(row[k])) for k in ("coef_error", "se_error")) < 1e-7
for row in read("unaffected_model_checks"):
    assert max(abs(float(row[k])) for k in ("max_coef_error", "max_covariance_error")) < 1e-7

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
summary = next(line for line in lines if "101+/solo premium" in line)
displayed = [float(x.strip()) for x in summary.strip().removesuffix(r"\\").split("&")[1:]]
for (sample, group), value in zip([(s, g) for s in models for g in ("Informal", "Formal")], displayed):
    row = next(r for r in contrasts if r["sample"] == sample and r["group"] == group and r["size"] == "101+"
               and r["reference"] == "Solo" and r["clustering"] == "Sector-department")
    assert abs(value-float(row["premium"])) < .05001
print(f"PASS: {len(contrasts)} full-covariance contrasts, {checked} table coefficients, sample accounting, harmonization, and reference invariance.")
