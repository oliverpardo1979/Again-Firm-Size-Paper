"""Read the LaTeX back and compare every regression-table row with aggregate outputs."""
import csv
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/regression_output"
SIZES = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]
count = 0


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


contrasts = {(r["model"], r["reference"], r["size"], r["parameter"]): r for r in read("contrasts")}
coefficients = {(r["model"], r["term"]): r for r in read("coefficients")}


def lines(file):
    return (ROOT / "Paper/sections" / file).read_text(encoding="utf-8").splitlines()


def row_at(text, label):
    found = [i for i, line in enumerate(text) if line.split("&")[0].strip() == label]
    assert len(found) == 1, (label, found)
    return found[0]


def cells(text):
    return [c.strip().removesuffix(r"\\").strip() for c in text.split("&")]


def expected_stars(r):
    p = float(r["p.value"])
    return "***" if p < .01 else "**" if p < .05 else "*" if p < .1 else ""


def check_coef(cell, row):
    global count
    match = re.match(r"(-?\d+\.\d+)(\**)", cell)
    assert match, cell
    assert abs(float(match[1])-float(row["estimate"])) <= .000500001, (cell, row)
    assert match[2] == expected_stars(row), (cell, row)
    count += 1


def check_se(cell, row):
    match = re.search(r"\((\d+\.\d+)\)", cell)
    assert match and abs(float(match[1])-float(row["std.error"])) <= .000500001, (cell, row)


def check_p(cell, row):
    p = float(row["p.value"])
    if "<" in cell:
        assert p < .001
    else:
        assert abs(float(cell)-p) <= .000500001, (cell, p)


for ref, suffix in [("Solo", ""), ("101+", "_101_reference"), ("11-19", "_11_19_reference")]:
    for family in ["common", "geo_common"]:
        file = f"regression_firm_size_table{suffix}.tex" if family == "common" else f"regression_local_geography_robustness{suffix}_table.tex"
        text = lines(file)
        for size in (s for s in SIZES if s != ref):
            index = row_at(text, f"Firm size: {size}")
            cs, ses = cells(text[index]), cells(text[index+1])
            for j in range(1, 5):
                r = contrasts[f"{family}{j}", ref, size, "common"]
                check_coef(cs[j], r)
                check_se(ses[j], r)
    text = lines("regression_formality_interaction_coefficients"+("_table" if ref == "Solo" else suffix)+".tex")
    for size in (s for s in SIZES if s != ref):
        index = row_at(text, size)
        cs, ses = cells(text[index]), cells(text[index+1])
        for j, parameter in enumerate(["informal", "interaction", "formal"], 1):
            r = contrasts["simple", ref, size, parameter]
            check_coef(cs[j], r)
            check_se(ses[j], r)
    text = lines(f"regression_local_geography_formality_robustness{suffix}_table.tex")
    group = "informal"
    for line in text:
        if r"\textit{Formal workers}" in line:
            group = "formal"
        if line.strip().startswith("Firm size:"):
            cs = cells(line)
            size = cs[0].split(": ")[1]
            for j in range(1, 5):
                r = contrasts[f"geo_interacted{j}", ref, size, group]
                check_coef(cs[j], r)
                check_se(cs[j], r)
    text = lines(f"regression_firm_size_trend_test{suffix}.tex")
    for size in (s for s in SIZES if s != ref):
        cs = cells(text[row_at(text, size)])
        r = contrasts["trend", ref, size, "common"]
        assert abs(float(cs[1])-float(r["estimate"])) <= .000050001
        assert abs(float(cs[2].strip("()"))-float(r["std.error"])) <= .000050001
        check_p(cs[3], r)
        assert abs(float(cs[4].replace(r"\%", ""))-100*math.expm1(17*float(r["estimate"]))) <= .050001
text = lines("regression_formal_101_contrasts_table.tex")
for r in read("formal_101_contrasts"):
    cs = cells(text[row_at(text, "Solo workers" if r["size"] == "Solo" else r["size"])])
    assert abs(float(cs[1].replace(r"\%", ""))-float(r["premium"])) <= .050001
    check_p(cs[2], r)
text = lines("regression_formality_gap_by_size_table.tex")
for r in read("formal_informal_gaps"):
    if r["model"] != "simple":
        continue
    index = row_at(text, r["size"])
    cs = cells(text[index])
    check_coef(cs[1], r)
    check_se(cells(text[index+1])[1], r)
    assert abs(float(cs[2].replace(r"\%", ""))-float(r["premium"])) <= .050001
    check_p(cs[3], r)
text = lines("regression_elasticity_benchmark_table.tex")
for sample, label in [("raw", "No controls"), ("full", "Full sample"), ("formal", "Formal workers"), ("informal", "Informal workers")]:
    cs = next(cells(line) for line in text if f"Colombia (GEIH) & {label} &" in line)
    r = coefficients[f"elasticity_{sample}", "log_size_midpoint"]
    check_coef(cs[2], r)
    check_se(cs[3], r)
text = lines("regression_polynomial_size_profile_table.tex")
for sample, label in [("raw", "Raw"), ("full", "Full sample"), ("formal", "Formal workers"), ("informal", "Informal workers")]:
    index = row_at(text, label)
    cs, ses = cells(text[index]), cells(text[index+1])
    for j, term in enumerate(["log_size_midpoint", "log_size_midpoint_sq"], 1):
        r = coefficients[f"polynomial_{sample}", term]
        check_coef(cs[j], r)
        check_se(ses[j], r)
    r = next(r for r in read("polynomial_101_contrasts") if r["sample"] == sample)
    assert abs(float(re.match(r"(-?\d+\.\d+)", cs[3])[1])-float(r["premium"])) <= .050001
    assert cs[3].split(r"\%")[1] == expected_stars(r)

# The descriptive table uses current endpoint data and must not be changed by regression reconciliation.
text = lines("descriptive_core_size_2008_2025_table.tex")
desc = {(r["anio"], r["tamano_empresa"]): r for r in read("descriptive_reference_check")}
for size in SIZES+["All workers"]:
    cs = cells(text[row_at(text, size)])
    for j, year in enumerate(["2008", "2025"]):
        r = desc[year, size]
        assert abs(float(cs[1+j].replace(r"\%", ""))-float(r["share"])) <= .050001
        assert abs(float(cs[3+j].replace(",", ""))-float(r["hourly_income"])) <= .50001
        assert abs(float(cs[5+j])-float(r["ratio_to_solo"])) <= .050001
    cagr = 100*((float(desc["2025", size]["hourly_income"])/float(desc["2008", size]["hourly_income"]))**(1/17)-1)
    assert abs(float(cs[7].replace(r"\%", ""))-cagr) <= .050001
print(f"PASS: {count} coefficient/SE/significance cells, all 19 regression tables, and the descriptive endpoint table.")
