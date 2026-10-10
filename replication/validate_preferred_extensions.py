"""Independently reconstruct preferred contrasts and audit the manuscript references."""
import csv
import itertools
import json
import math
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/preferred_output"
sys.path.insert(0, str(ROOT / "build/qa_dependencies"))
import numpy as np
from scipy.stats import t


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


models = {r["model"]: r for r in read("models")}
coefs = {}
for row in read("coefficients"):
    coefs.setdefault(row["model"], {})[row["term"]] = float(row["estimate"])

checked = 0
for name in ["profiles", "formal_informal_gaps", "clustering_sensitivity", "annual_profiles", "endpoint_changes",
             "elasticities", "extension_clustering_sensitivity", "coefficients"]:
    for row in read(name):
        b, se, df = (float(row[k]) for k in ("estimate", "std.error", "df"))
        assert se > 0 and df > 0
        assert abs(float(row["premium"]) - 100*math.expm1(b)) < 1e-7
        assert abs(float(row["p.value"])-2*t.sf(abs(b/se), df)) < 1e-10
        for side, sign in [("low", -1), ("high", 1)]:
            bound = b+sign*t.ppf(.975, df)*se
            assert abs(float(row[f"conf.{side}"])-bound) < 1e-8
            assert abs(float(row[f"ci_{side}"])-100*math.expm1(bound)) < 1e-5
        checked += 1


def term(model, *pieces):
    candidates = {":".join(p) for p in itertools.permutations(pieces)}
    found = candidates.intersection(coefs[model])
    assert len(found) == 1, (model, pieces, found)
    return found.pop()


def profile(model, size, group, post=False):
    if size == "Solo":
        return {}
    base = f"tamano_empresa::{size}"
    z = {term(model, base): 1.0}
    if group == "Formal":
        z[term(model, base, "formal")] = 1.0
    if post:
        z[term(model, base, "post")] = 1.0
        if group == "Formal":
            z[term(model, base, "formal", "post")] = 1.0
    return z


def subtract(a, b):
    return {k: a.get(k, 0)-b.get(k, 0) for k in set(a) | set(b)}


cov = {}
for model in ("preferred", "endpoints", "elasticity_interacted"):
    for row in read("covariance_"+model):
        cov[model, row["clustering"], row["term1"], row["term2"]] = float(row["covariance"])
    names = list(coefs[model])
    for clustering in ("Sector", "Sector-department"):
        matrix = np.array([[cov[model, clustering, a, b] for b in names] for a in names])
        assert np.max(np.abs(matrix-matrix.T)) < 1e-10
        assert np.linalg.eigvalsh(matrix).min() > -1e-8


def check_contrast(model, row, z, clustering="Sector-department"):
    b = sum(weight*coefs[model][key] for key, weight in z.items())
    var = sum(wa*wb*cov[model, clustering, a, b] for a, wa in z.items() for b, wb in z.items())
    assert abs(b-float(row["estimate"])) < 1e-9
    assert abs(math.sqrt(var)-float(row["std.error"])) < 1e-9


for row in read("profiles"):
    z = subtract(profile("preferred", row["size"], row["group"]), profile("preferred", row["reference"], row["group"]))
    check_contrast("preferred", row, z)
for row in read("formal_informal_gaps"):
    z = subtract(profile("preferred", row["size"], "Formal"), profile("preferred", row["size"], "Informal"))
    z["formal"] = 1
    check_contrast("preferred", row, z)
annual = {(r["year"], r["size"], r["group"]): r for r in read("annual_profiles")}
for row in read("endpoint_changes"):
    early = profile("endpoints", row["size"], row["group"])
    late = profile("endpoints", row["size"], row["group"], True)
    check_contrast("endpoints", row, subtract(late, early))
    for year in ("2008", "2025"):
        assert abs(float(row["premium_"+year])-float(annual[year, row["size"], row["group"]]["premium"])) < 1e-7
for row in read("elasticities"):
    if row["sample"] in ("raw", "common"):
        continue
    z = {"log_size_midpoint": 1}
    interaction = term("elasticity_interacted", "log_size_midpoint", "formal")
    if row["sample"] == "Formal":
        z[interaction] = 1
    elif row["sample"] == "Formal-minus-informal":
        z = {interaction: 1}
    check_contrast("elasticity_interacted", row, z)
for row in read("extension_clustering_sensitivity"):
    if row["exercise"] == "Endpoint change, 101+/solo":
        model = "endpoints"
        z = subtract(profile(model, "101+", row["group"], True), profile(model, "101+", row["group"]))
    else:
        model = "elasticity_interacted"
        z = {"log_size_midpoint": 1}
        if row["group"] == "Formal":
            z[term(model, "log_size_midpoint", "formal")] = 1
    check_contrast(model, row, z, row["clustering"])
assert sum(int(r["n"]) for k, r in models.items() if k.startswith("year")) == int(models["preferred"]["n"]) == 5268375
assert int(models["endpoints"]["n"]) == int(models["year2008"]["n"])+int(models["year2025"]["n"])
assert len(annual) == 17*8*2 and not any(k[0] == "2020" for k in annual)
assert max(abs(float(r["error"])) for r in read("endpoint_replication_check")) < 1e-7

def table_rows(filename):
    text = (ROOT / "Paper/sections" / filename).read_text(encoding="utf-8")
    group = None
    result = []
    for line in text.splitlines():
        heading = re.search(r"\\textit\{(Formal|Informal) workers\}", line)
        if heading:
            group = heading[1]
        if " & " in line:
            cells = [re.sub(r"\*|\\%|[()]", "", x.strip()) for x in line.strip().removesuffix(r"\\").split(" & ")]
            result.append((group, cells))
    return result


def check_p(display, row):
    p = float(row["p.value"])
    if p < .001:
        assert display == "$<0.001$"
    else:
        assert abs(float(display)-p) <= (.000051 if .0495 <= p <= .0505 else .000501)


gaps = {r["size"]: r for r in read("formal_informal_gaps")}
table_cells = 0
for _, cells in table_rows("regression_preferred_formality_gap_table.tex"):
    if cells[0] in gaps:
        r = gaps[cells[0]]
        assert abs(float(cells[1])-float(r["estimate"])) < .000501
        assert abs(float(cells[2])-float(r["premium"])) < .05001
        check_p(cells[3], r)
        table_cells += 3
endpoint = {(r["group"], r["size"]): r for r in read("endpoint_changes")}
for group, cells in table_rows("regression_preferred_endpoint_changes_table.tex"):
    if (group, cells[0]) in endpoint:
        r = endpoint[group, cells[0]]
        early, late = float(r["premium_2008"]), float(r["premium_2025"])
        assert abs(float(cells[1])-early) < .05001
        assert abs(float(cells[2])-late) < .05001
        assert abs(float(cells[3])-(late-early)) < .05001
        check_p(cells[4], r)
        table_cells += 4
elasticities = {r["sample"]: r for r in read("elasticities")}
mapping = {"No controls": "raw", "Common-slope model": "common", "Formal workers": "Formal", "Informal workers": "Informal"}
for _, cells in table_rows("regression_preferred_elasticity_table.tex"):
    if cells[0] == "Colombia GEIH":
        r = elasticities[mapping[cells[1]]]
        assert abs(float(cells[2])-float(r["estimate"])) < .000501
        assert abs(float(cells[3])-float(r["std.error"])) < .000501
        table_cells += 2
assert table_cells == 99, table_cells

# Check the compiled source tree, not unused fragments or stale auxiliary files.
def expand(path):
    text = path.read_text(encoding="utf-8")
    return re.sub(r"\\input\{([^}]+)\}", lambda m: expand(ROOT / (m[1]+("" if m[1].endswith(".tex") else ".tex"))), text)


source = expand(ROOT / "main.tex")
labels = re.findall(r"\\label\{([^}]+)\}", source)
assert len(labels) == len(set(labels)), "Duplicate labels"
refs = re.findall(r"\\(?:eqref|ref)\{([^}]+)\}", source)
assert set(refs) <= set(labels), set(refs)-set(labels)
body, appendix = source.split(r"\appendix", 1)
appendix_labels = [x for x in re.findall(r"\\label\{([^}]+)\}", appendix) if x.startswith(("tab:", "fig:"))]
assert all(r"\ref{"+label+"}" in body for label in appendix_labels), [x for x in appendix_labels if r"\ref{"+x+"}" not in body]
for image in re.findall(r"\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}", source):
    for lang in ("en", "es"):
        assert (ROOT / "Paper/figures" / image.replace(r"\figurelang", lang)).is_file(), image
citations = set()
for group in re.findall(r"\\cite\w*\{([^}]+)\}", source):
    citations.update(x.strip() for x in group.split(","))
bib = (ROOT / "Paper/references.bib").read_text(encoding="utf-8")
keys = set(re.findall(r"@\w+\s*\{\s*([^,]+)", bib))
assert citations <= keys, citations-keys
abstracts = []
for name in ("main.tex", "manuscript_no_author_details.tex"):
    original = subprocess.check_output(["git", "show", "HEAD:"+name], cwd=ROOT, encoding="utf-8")
    current = (ROOT / name).read_text(encoding="utf-8")
    pattern = r"\\begin\{abstract\}\s*(.*?)\s*\\end\{abstract\}"
    before = re.search(pattern, original, re.S)[1]
    after = re.search(pattern, current, re.S)[1]
    assert before == after
    abstracts.append(after)
assert abstracts[0] == abstracts[1] and len(abstracts[0].split()) == 114
report = dict(models=len(models), arithmetic_rows_checked=checked, reference_contrasts_checked=len(read("profiles")),
              endpoint_tests=len(read("endpoint_changes")), annual_profiles=len(annual), labels=len(labels), displayed_table_cells_checked=table_cells,
              cited_bibliography_entries=len(citations), appendix_tables_figures_referenced=len(appendix_labels),
              approved_abstract_words=114, preferred_sample=5268375, status="passed")
print(json.dumps(report, indent=2))
