"""Independent arithmetic and consistency checks on the published regression outputs."""
import csv
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/regression_output"
local_dependencies = ROOT / "build/qa_dependencies"
if local_dependencies.is_dir():
    sys.path.insert(0, str(local_dependencies))
from scipy.stats import t


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


contrasts = read("contrasts")
lookup = {(r["model"], r["reference"], r["size"], r["parameter"]): r for r in contrasts}
for name in ["contrasts", "coefficients", "annual_profiles", "formal_informal_gaps", "formal_101_contrasts", "polynomial_101_contrasts"]:
    for row in read(name):
        b, se, df, p = [float(row[k]) for k in ["estimate", "std.error", "df", "p.value"]]
        assert se > 0 and df > 0
        assert abs(float(row["premium"]) - 100*math.expm1(b)) < 1e-8
        assert abs(p - 2*t.sf(abs(b/se), df)) < 1e-10
        for side, sign in [("low", -1), ("high", 1)]:
            log_bound = b + sign*t.ppf(.975, df)*se
            assert abs(float(row[f"conf.{side}"]) - log_bound) < 1e-8
            assert abs(float(row[f"ci_{side}"]) - 100*math.expm1(log_bound)) < 1e-6

for row in contrasts:
    model, ref, size, param = [row[k] for k in ["model", "reference", "size", "parameter"]]
    base = lambda s: 0.0 if s == "Solo" else float(lookup[model, "Solo", s, param]["estimate"])
    assert abs(float(row["estimate"]) - (base(size)-base(ref))) < 1e-10
    reverse = lookup.get((model, size, ref, param))
    if reverse:
        assert abs(float(row["estimate"]) + float(reverse["estimate"])) < 1e-10
        assert abs(float(row["std.error"]) - float(reverse["std.error"])) < 1e-10
        assert abs(float(row["p.value"]) - float(reverse["p.value"])) < 1e-10

for size in ["2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]:
    for param in ["informal", "interaction", "formal"]:
        a = lookup["simple", "Solo", size, param]
        b = lookup["geo_interacted1", "Solo", size, param]
        assert abs(float(a["estimate"])-float(b["estimate"])) < 1e-10
    a = lookup["common4", "Solo", size, "common"]
    b = lookup["geo_common1", "Solo", size, "common"]
    assert abs(float(a["estimate"])-float(b["estimate"])) < 1e-10

for row in read("reference_invariance_check"):
    assert max(abs(float(row[k])) for k in ["coef_error", "se_error"]) < 1e-7
for row in read("preferred_replication_check"):
    assert max(abs(float(v)) for k, v in row.items() if k.endswith("error")) < 1e-7

models = {r["model"]: r for r in read("models")}
assert models["simple"]["sample_hash"] == models["geo_interacted1"]["sample_hash"]
assert int(models["common1"]["n"]) == int(models["simple"]["n"]) == 5426316
assert int(models["geo_interacted4"]["n"]) == 5426174
assert int(models["simple"]["df"]) == 16
assert int(models["geo_interacted4"]["df"]) == 558
with (ROOT / "replication/output/preferred_coefficients.csv").open(encoding="utf-8-sig", newline="") as f:
    cached_preferred = list(csv.DictReader(f))
new_preferred = {r["term"]: r for r in read("coefficients") if r["model"] == "geo_interacted4"}
assert set(new_preferred) == {r["term"] for r in cached_preferred}
for row in cached_preferred:
    new = new_preferred[row["term"]]
    assert abs(float(row["estimate"])-float(new["estimate"])) < 1e-7
    assert abs(float(row["se"])-float(new["std.error"])) < 1e-7
print(f"PASS: {len(models)} models, {len(contrasts)} contrasts, t-based inference, percentage transformations,")
print("reference invariance, identical point estimates across clustering conventions, and preferred-model replication.")
print("Preferred coefficients and standard errors agree across the regression and income-scenario pipelines.")
