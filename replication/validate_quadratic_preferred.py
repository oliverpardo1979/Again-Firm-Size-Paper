"""Reconstruct quadratic profiles and Wald tests independently from aggregate matrices."""
import csv
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/quadratic_output"
PREFERRED = ROOT / "replication/preferred_output"
sys.path.insert(0, str(ROOT / "build/qa_dependencies"))
import numpy as np
from scipy.stats import f, t


def read(folder, name):
    with (folder / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def close(a, b, tolerance=1e-8):
    assert math.isclose(float(a), float(b), rel_tol=tolerance, abs_tol=tolerance), (a, b)


def matrix(rows, terms):
    lookup = {(r["term1"], r["term2"]): float(r["covariance"]) for r in rows}
    assert len(lookup) == len(terms)**2
    v = np.array([[lookup[a, b] for b in terms] for a in terms])
    assert np.allclose(v, v.T, atol=1e-10)
    assert np.linalg.eigvalsh(v).min() > -1e-9
    return v


def interaction_index(terms, term):
    found = set(terms).intersection({f"{term}:formal", f"formal:{term}"})
    assert len(found) == 1
    return terms.index(found.pop())


raw = read(OUT, "raw_coefficients")
covariances = read(OUT, "covariances")
preferred_rows = [r for r in read(PREFERRED, "coefficients") if r["model"] == "preferred"]
terms = [r["term"] for r in preferred_rows]
beta = np.array([float(r["estimate"]) for r in preferred_rows])
preferred_cov = read(PREFERRED, "covariance_preferred")
V = {g: matrix([r for r in preferred_cov if r["clustering"] == g], terms)
     for g in ("Sector-department", "Sector")}
sizes = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]
maps = {}
for group in ("Formal", "Informal"):
    a = np.zeros((8, len(terms)))
    for j, size in enumerate(sizes[1:]):
        term = f"tamano_empresa::{size}"
        a[j, terms.index(term)] = 1
        if group == "Formal":
            a[j, interaction_index(terms, term)] = 1
    maps[group] = a

models = {}
for top in (101, 150, 250):
    rows = [r for r in raw if int(r["top"]) == top]
    names = [r["term"] for r in rows]
    b = np.array([float(r["estimate"]) for r in rows])
    cov = matrix([r for r in covariances if int(r["top"]) == top and r["clustering"] == "Sector-department"], names)
    assert {"z", "z2"}.issubset(names)
    interaction_index(names, "z")
    interaction_index(names, "z2")
    assert not any("z3" in name or "poly(" in name for name in names)
    assert all(int(r["df"]) == 558 for r in rows)
    models[top] = (names, b, cov)


def profile(top, group, z, term=None):
    names, b, cov = models[top]
    a1, a2 = np.zeros(len(names)), np.zeros(len(names))
    a1[names.index("z")] = 1
    a2[names.index("z2")] = 1
    if group == "Formal":
        a1[interaction_index(names, "z")] = 1
        a2[interaction_index(names, "z2")] = 1
    a = a1 if term == "linear" else a2 if term == "quadratic" else z*a1+z*z*a2
    return float(a@b), math.sqrt(max(0, float(a@cov@a)))


checks = 0
for filename in ("coefficients", "category_predictions", "curves"):
    for row in read(OUT, filename):
        top, group = int(row["top"]), row["group"]
        z = math.log(float(row["size_value"])) if "size_value" in row else 0
        if filename == "category_predictions":
            assigned = [1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, top]
            close(row["size_value"], assigned[sizes.index(row["size"])])
        b, se = profile(top, group, z, row.get("term"))
        close(row["estimate"], b)
        close(row["std.error"], se)
        close(row["premium"], 100*math.expm1(b))
        for side, sign in (("low", -1), ("high", 1)):
            bound = b+sign*t.ppf(.975, 558)*se
            close(row[f"conf.{side}"], bound)
            close(row[f"ci_{side}"], 100*math.expm1(bound))
        if se > 0:
            close(row["p.value"], 2*t.sf(abs(b/se), 558))
        else:
            close(b, 0)
        checks += 1

tests = read(OUT, "restriction_tests")
for row in tests:
    top = int(row["top"])
    z = np.log([2.5, 4.5, 8, 15, 25, 40.5, 75.5, top])
    design = np.column_stack((z, z*z))
    # Use the first and last categories as anchors, unlike the R QR construction.
    anchors = design[[0, 7], :]
    L = np.zeros((6, 8))
    for k, j in enumerate(range(1, 7)):
        L[k, j] = 1
        L[k, [0, 7]] -= design[j, :]@np.linalg.inv(anchors)
    assert np.max(np.abs(L@design)) < 1e-10
    restrictions = {g: L@maps[g] for g in maps}
    restrictions["Joint"] = np.vstack((restrictions["Informal"], restrictions["Formal"]))
    R = restrictions[row["group"]]
    r = R@beta
    covariance = R@V[row["clustering"]]@R.T
    assert np.linalg.matrix_rank(covariance) == len(R)
    W = float(r@np.linalg.solve(covariance, r))
    q = len(R)
    df = 558 if row["clustering"] == "Sector-department" else 16
    close(row["wald"], W, tolerance=1e-6)
    close(row["F_statistic"], W/q, tolerance=1e-6)
    close(row["p.value"], f.sf(W/q, q, df), tolerance=1e-10)
    assert int(row["restrictions"]) == int(row["df_num"]) == q
    assert int(row["df_den"]) == df

for row in read(OUT, "summaries"):
    top, group = int(row["top"]), row["group"]
    linear, _ = profile(top, group, 0, "linear")
    quadratic, _ = profile(top, group, 0, "quadratic")
    close(row["linear"], linear)
    close(row["quadratic"], quadratic)
    turn = math.exp(-linear/(2*quadratic))
    close(row["turning_size"], turn)
    assert (row["turn_within_support"] == "TRUE") == (1 < turn < top)
    close(row["elasticity_solo"], linear)
    close(row["elasticity_top"], linear+2*quadratic*math.log(top))
    assert int(row["n"]) == 5268375

table = (ROOT / "Paper/sections/regression_preferred_quadratic_table.tex").read_text(encoding="utf-8")
for row in read(OUT, "coefficients"):
    if int(row["top"]) == 150:
        assert f'{float(row["estimate"]):.4f}' in table
        assert f'({float(row["std.error"]):.4f})' in table
sensitivity = (ROOT / "Paper/sections/regression_preferred_quadratic_sensitivity_table.tex").read_text(encoding="utf-8")
for row in read(OUT, "category_predictions"):
    if row["size"] == "101+":
        assert f'{float(row["premium"]):.1f}' in sensitivity
for lang in ("en", "es"):
    path = ROOT / f"Paper/figures/preferred_quadratic_{lang}.png"
    assert path.stat().st_size > 10000
assert len(tests) == 18
assert (OUT / "provenance.txt").read_text().splitlines()[0] == (PREFERRED / "provenance.txt").read_text().splitlines()[0]
print(json.dumps({"status": "passed", "models": 3, "preferred_sample": 5268375,
    "profile_and_coefficient_checks": checks, "independent_Wald_tests": len(tests),
    "top_bin_assignments": [101, 150, 250], "degree": 2}, indent=2))
