"""Build appendix inference comparisons from validated aggregate audit outputs."""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/inference_audit_output"
SECTIONS = ROOT / "Paper/sections"


def read(name):
    with (OUT / name).open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


conventional = read("conventional.csv")
include_bootstrap = "--include-bootstrap" in sys.argv
wild = read("wild_bootstrap.csv") if include_bootstrap else []
assert len(conventional) == 180
if include_bootstrap:
    assert len(wild) == 135


def select(rows, label, clustering):
    matches = [r for r in rows if r["contrast"] == label and r["clustering"] == clustering]
    assert len(matches) == 1, (label, clustering)
    return matches[0]


def pvalue(value):
    p = float(value)
    assert 0 <= p <= 1
    return "$<0.001$" if p < .001 else f"{p:.4f}"


panels = [
    ("A. Within-formality log-wage gaps", [
        ("Formal 101+/solo", "Formal 101+/solo"),
        ("Informal 101+/solo", "Informal 101+/solo"),
        ("Formal-minus-informal 101+/solo", "Formal minus informal, 101+/solo"),
        *[(f"Formal 101+/{size}", f"Formal 101+/{size.replace('-', '--')}")
          for size in ["2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100"]],
        ("Informal 101+/11-19", "Informal 101+/11--19"),
    ]),
    ("B. Formal-minus-informal log-wage gaps", [
        ("Formal-informal at " + size, size.replace("-", "--")) for size in ["Solo", "11-19", "101+"]
    ]),
    ("C. Change in the 101+/solo log-wage gap, 2008--2025", [
        (group + " change 101+/solo 2008-2025", group) for group in ["Formal", "Informal"]
    ]),
    ("D. Approximate firm-size elasticities", [
        (group + " elasticity", group) for group in ["Formal", "Informal", "Formal-minus-informal"]
    ]),
]


def line(values):
    return "    " + " & ".join(values) + r" \\"


def make_table(bootstrap):
    clusters = ["Sector", "Department", "Two-way sector + department"]
    if not bootstrap:
        clusters.insert(0, "Sector-department")
    headings = ["Contrast", "Estimate"] + (["$p$ (SD)"] if not bootstrap else [])
    headings += ["$p$ (S)", "$p$ (D)", "$p$ (S+D)"]
    rows = []
    for title, entries in panels:
        if rows:
            rows.append(r"    \midrule")
        rows.append(r"    \multicolumn{" + str(len(headings)) + r"}{l}{\textit{" + title + r"}} \\")
        for key, display in entries:
            baseline = select(conventional, key, "Sector-department")
            values = [display, f'{float(baseline["estimate"]):.3f}']
            for cluster in clusters:
                r = select(wild if bootstrap else conventional, key, cluster)
                assert abs(float(r["estimate"]) - float(baseline["estimate"])) < 1e-8
                value = pvalue(r["p_wild"] if bootstrap else r["p"])
                if bootstrap:
                    assert int(r["finite_boot_t"]) + int(r["discarded_boot_t"]) == 9999
                    if int(r["discarded_boot_t"]):
                        assert key == "Formal change 101+/solo 2008-2025" and cluster == clusters[-1]
                        assert int(r["discarded_boot_t"]) == 209
                        value += r"$^{\dagger}$"
                values.append(value)
            rows.append(line(values))
    if bootstrap:
        filename = "regression_inference_bootstrap_table.tex"
        caption = "Wild cluster bootstrap tests for preferred-model contrasts"
        label = "tab:preferred-wild-bootstrap"
        notes = (
            r"Contrasts and specifications match Table~\ref{tab:preferred-clustering-comparison}. "
            r"S and D denote sector and department clustering. S+D uses two-way covariance with bootstrap weights "
            r"drawn by sector. Tests are two-sided WCR11 with the null imposed, Rademacher weights, and 9,999 draws. "
            r"$\dagger$ The package discarded 209 invalid bootstrap $t$-statistics for this test, leaving 9,790 draws. "
            r"All other displayed tests retained 9,999 valid draws. Tests are pointwise, without multiple-testing adjustment."
        )
    else:
        filename = "regression_inference_clustering_table.tex"
        caption = "Clustering sensitivity of preferred-model contrasts"
        label = "tab:preferred-clustering-comparison"
        notes = (
            r"Panels A--B use Equation~(\ref{eq:main}), C uses the joint endpoint model in "
            r"Equation~(\ref{eq:preferred-dynamics}), and D uses Equation~(\ref{eq:preferred-elasticity}). "
            r"Estimates in A--C are in log points, not percentages or percentage-point changes. "
            r"SD denotes sector-department intersections, S sector, D department, and S+D two-way sector and department clustering. "
            r"Two-sided $t$ tests use the number of clusters minus one degree of freedom, "
            r"with the smaller cluster count for S+D."
        )
    spec = "@{}p{0.40\\textwidth}" + "r" * (len(headings) - 1) + "@{}"
    text = "\n".join([
        r"\begin{table}[htbp]", r"  \centering", "  \\caption{" + caption + "}",
        "  \\label{" + label + "}", r"  \small", r"  \setlength{\tabcolsep}{5pt}",
        "  \\begin{tabular}{" + spec + "}", r"    \toprule", line(headings),
        r"    \midrule", *rows, r"    \bottomrule", r"  \end{tabular}",
        r"  \vspace{0.3em}", r"  \begin{minipage}{0.98\textwidth}", r"    \footnotesize",
        "    Notes: " + notes, r"  \end{minipage}", r"\end{table}", "",
    ])
    (SECTIONS / filename).write_text(text, encoding="utf-8", newline="\n")


make_table(False)
if include_bootstrap:
    make_table(True)
print("Generated inference table from 19 audited contrasts. Bootstrap is opt-in.")
