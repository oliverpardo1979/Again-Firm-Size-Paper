"""Refresh numerical rows only, preserving the manuscript's captions and notes."""
import csv
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/regression_output"
SECTIONS = ROOT / "Paper/sections"
SIZES = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]
CHANGES = []


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


CONTRASTS = read("contrasts")
MODELS = {r["model"]: r for r in read("models")}
COEFS = read("coefficients")


def select(rows, **keys):
    found = [r for r in rows if all(r[k] == v for k, v in keys.items())]
    assert len(found) == 1, (keys, len(found))
    return found[0]


def estimate(model, ref, size, parameter="common"):
    return select(CONTRASTS, model=model, reference=ref, size=size, parameter=parameter)


def stars(row):
    p = float(row["p.value"])
    return "***" if p < .01 else "**" if p < .05 else "*" if p < .10 else ""


def coef(row):
    return f'{float(row["estimate"]):.3f}{stars(row)}'


def se(row):
    return f'({float(row["std.error"]):.3f})'


def premium(row):
    return f'{float(row["premium"]):.1f}\\%'


def pvalue(row):
    p = float(row["p.value"])
    return "$<0.001$" if p < .001 else f"{p:.3f}"


def line(cells):
    return "    " + " & ".join(cells) + r" \\"


def patch_rows(file, rows, stats=None):
    path = SECTIONS / file
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines()
    seen = set()
    index = 0
    while index < len(lines):
        label = lines[index].split(" & ")[0].strip()
        if label in rows:
            replacement = rows[label]
            old_count = 2 if index+1 < len(lines) and lines[index+1].lstrip().startswith("& (") else 1
            old = lines[index:index+old_count]
            lines[index:index+old_count] = replacement
            if old != replacement:
                CHANGES.append({"file": file, "row": label, "before": " | ".join(old), "after": " | ".join(replacement)})
            seen.add(label)
            index += len(replacement)
        elif stats and label in ("Observations", "$R^2$"):
            values = [f'{int(MODELS[m]["n"]):,}' if label == "Observations" else f'{float(MODELS[m]["r2"]):.3f}' for m in stats]
            lines[index] = line([label, *values])
            index += 1
        else:
            index += 1
    assert seen == set(rows), (file, set(rows)-seen)
    result = "\n".join(lines) + "\n"
    if result != original:
        path.write_text(result, encoding="utf-8", newline="\n")


for ref, suffix in [("Solo", ""), ("101+", "_101_reference"), ("11-19", "_11_19_reference")]:
    for family in ("common", "geo_common"):
        if family == "common":
            filename = f"regression_firm_size_table{suffix}.tex"
        else:
            filename = f"regression_local_geography_robustness{suffix}_table.tex"
        model_names = [f"{family}{j}" for j in range(1, 5)]
        rows = {}
        for size in (s for s in SIZES if s != ref):
            values = [estimate(m, ref, size) for m in model_names]
            label = f"Firm size: {size}"
            rows[label] = [line([label, *map(coef, values)]), line(["", *map(se, values)])]
        patch_rows(filename, rows, stats=model_names)

    filename = "regression_formality_interaction_coefficients" + ("_table" if ref == "Solo" else suffix) + ".tex"
    rows = {}
    for size in (s for s in SIZES if s != ref):
        values = [estimate("simple", ref, size, p) for p in ("informal", "interaction", "formal")]
        rows[size] = [line([size, *map(coef, values)]), line(["", *map(se, values)])]
    patch_rows(filename, rows)

    rows = {}
    for size in (s for s in SIZES if s != ref):
        r = estimate("trend", ref, size)
        rows[size] = [line([size, f'{float(r["estimate"]):.4f}', f'({float(r["std.error"]):.4f})',
            f'{float(r["p.value"]):.3f}', f'{100*math.expm1(17*float(r["estimate"])):.1f}\\%'])]
    patch_rows(f"regression_firm_size_trend_test{suffix}.tex", rows)

    # The two panel labels repeat firm-size labels, so update panels independently.
    path = SECTIONS / f"regression_local_geography_formality_robustness{suffix}_table.tex"
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines()
    group = None
    count = 0
    for j, text in enumerate(lines):
        if r"\textit{Informal workers}" in text:
            group = "informal"
        elif r"\textit{Formal workers}" in text:
            group = "formal"
        if text.strip().startswith("Firm size:"):
            size = text.split(" & ")[0].split(": ")[1]
            values = [estimate(f"geo_interacted{k}", ref, size, group) for k in range(1, 5)]
            lines[j] = line([f"Firm size: {size}", *[coef(r) + r" {\scriptsize " + se(r) + "}" for r in values]])
            if text != lines[j]:
                CHANGES.append({"file": path.name, "row": f"{group} {size}", "before": text, "after": lines[j]})
            count += 1
    assert count == 16
    path.write_text("\n".join(lines)+"\n", encoding="utf-8", newline="\n")

rows = {}
for r in read("formal_101_contrasts"):
    label = "Solo workers" if r["size"] == "Solo" else r["size"]
    rows[label] = [line([label, premium(r), pvalue(r)])]
patch_rows("regression_formal_101_contrasts_table.tex", rows)
rows = {}
for r in read("formal_informal_gaps"):
    if r["model"] == "simple":
        label = r["size"]
        rows[label] = [line([label, coef(r), premium(r), pvalue(r)]), line(["", se(r), "", ""])]
patch_rows("regression_formality_gap_by_size_table.tex", rows)

rows = {}
for sample, label in [("raw", "No controls"), ("full", "Full sample"), ("formal", "Formal workers"), ("informal", "Informal workers")]:
    r = select(COEFS, model=f"elasticity_{sample}", term="log_size_midpoint")
    rows[f"Colombia (GEIH) & {label}"] = [line(["Colombia (GEIH)", label, coef(r), se(r)])]
path = SECTIONS / "regression_elasticity_benchmark_table.tex"
text = path.read_text(encoding="utf-8")
for key, replacement in rows.items():
    pattern = re.compile(r"^\s*"+re.escape(key)+r" & .*?$", re.MULTILINE)
    text, count = pattern.subn(lambda m: replacement[0], text)
    assert count == 1
path.write_text(text, encoding="utf-8", newline="\n")

rows = {}
for sample, label in [("raw", "Raw"), ("full", "Full sample"), ("formal", "Formal workers"), ("informal", "Informal workers")]:
    vals = [select(COEFS, model=f"polynomial_{sample}", term=t) for t in ("log_size_midpoint", "log_size_midpoint_sq")]
    r = select(read("polynomial_101_contrasts"), sample=sample)
    rows[label] = [line([label, *map(coef, vals), premium(r)+stars(r)]), line(["", *map(se, vals), ""])]
patch_rows("regression_polynomial_size_profile_table.tex", rows)

# Keep the pre-existing machine-readable preferred table synchronized too.
path = ROOT / "Paper/tables/regression_local_geography_formality_robustness.csv"
with path.open(encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    fields = reader.fieldnames
    data = list(reader)
for r in data:
    for group in ("informal", "formal"):
        new = estimate("geo_interacted"+r["model"].strip("()"), r["reference_size"], r["size"], group)
        for suffix, field in [("estimate", "estimate"), ("se", "std.error"), ("p", "p.value")]:
            assert f"{group}_{suffix}" in r
            r[f"{group}_{suffix}"] = new[field]
with path.open("w", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(data)

path = ROOT / "Paper/tables/regression_polynomial_size_profile.csv"
with path.open(encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    fields = reader.fieldnames
    data = list(reader)
for r, sample in zip(data, ["raw", "full", "formal", "informal"]):
    for suffix, term in [("log_size", "log_size_midpoint"), ("log_size_sq", "log_size_midpoint_sq")]:
        new = select(COEFS, model=f"polynomial_{sample}", term=term)
        for prefix, key in [("beta", "estimate"), ("se", "std.error"), ("p", "p.value")]:
            r[f"{prefix}_{suffix}"] = new[key]
    new = select(read("polynomial_101_contrasts"), sample=sample)
    for key, value in [("premium_101_solo", "premium"), ("se_premium_101_log", "std.error"), ("p_premium_101", "p.value")]:
        r[key] = new[value]
with path.open("w", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(data)

with (OUT / "table_changes.csv").open("w", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["file", "row", "before", "after"])
    writer.writeheader()
    writer.writerows(CHANGES)
print(f"Updated numerical rows in 19 regression tables. {len(CHANGES)} changed row groups.")
