"""Generate the preferred-model extension tables from aggregate, inspectable outputs."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/preferred_output"
SECTIONS = ROOT / "Paper/sections"


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def select(rows, **keys):
    result = [r for r in rows if all(r[k] == v for k, v in keys.items())]
    assert len(result) == 1, keys
    return result[0]


def pvalue(row):
    p = float(row["p.value"])
    if .0495 <= p <= .0505:
        return f"{p:.4f}"
    return "$<0.001$" if p < .001 else f"{p:.3f}"


def stars(row):
    p = float(row["p.value"])
    return "***" if p < .01 else "**" if p < .05 else "*" if p < .10 else ""


def line(values):
    return "    " + " & ".join(values) + r" \\"


def table(filename, caption, label, spec, header, rows, notes, size="small"):
    text = "\n".join([
        r"\begin{table}[htbp]", r"  \centering", "  \\caption{" + caption + "}",
        "  \\label{" + label + "}", "  \\" + size, "  \\begin{tabular}{" + spec + "}",
        r"    \toprule", line(header), r"    \midrule", *rows, r"    \bottomrule",
        r"  \end{tabular}", r"  \vspace{0.3em}", r"  \begin{minipage}{0.95\textwidth}",
        r"  \footnotesize", "  Notes: " + notes, r"  \end{minipage}", r"\end{table}", ""])
    (SECTIONS / filename).write_text(text, encoding="utf-8", newline="\n")


gaps = read("formal_informal_gaps")
table("regression_preferred_formality_gap_table.tex", "Formal-informal wage gaps in the preferred specification",
      "tab:preferred-formality-gap", "lccc", ["Firm size", "Log-wage gap", "Premium", "$p$-value"],
      [line([r["size"], f'{float(r["estimate"]):.3f}{stars(r)}', f'{float(r["premium"]):.1f}\\%', pvalue(r)]) for r in gaps],
      r"Each row compares formal with informal workers in the same firm-size category using Equation~(\ref{eq:main}). "
      r"The contrast is $\widehat\phi+\widehat\theta_g$, with $\theta_{Solo}=0$. Percent premiums are "
      r"$100[\exp(\widehat\phi+\widehat\theta_g)-1]$. Two-sided tests use sector-department-clustered standard errors. * "
      r"$p<0.10$, ** $p<0.05$, *** $p<0.01$.")

changes = read("endpoint_changes")
rows = []
for group in ("Formal", "Informal"):
    if rows:
        rows.append(r"    \midrule")
    rows.append(r"    \multicolumn{5}{l}{\textit{" + group + r" workers}} \\")
    for r in changes:
        if r["group"] == group:
            early, late = float(r["premium_2008"]), float(r["premium_2025"])
            rows.append(line([r["size"], f"{early:.1f}", f"{late:.1f}", f"{late-early:.1f}", pvalue(r)]))
table("regression_preferred_endpoint_changes_table.tex", "Changes in within-formality firm-size premiums, 2008--2025",
      "tab:preferred-endpoint-changes", "lrrrr", ["Firm size", "2008 (\\%)", "2025 (\\%)", "Change (pp)", "$p$-value"], rows,
      r"The reference is solo work within the same formality-year group. All worker and occupational-position slopes may differ by year. "
      r"Both years include sector-department fixed effects. Change (pp) is the 2025 premium minus the 2008 premium in percentage points. Changes are calculated before rounding. "
      r"Two-sided $p$-values test equality of the log-wage contrasts in Equation~(\ref{eq:preferred-dynamics}), using a joint endpoint regression "
      r"and sector-department clustering to retain cross-year covariance. Tests are pointwise, not adjusted for multiple comparisons.")

elasticities = read("elasticities")
rows = [line(["Diegmann et al. (2026)", "No worker controls", "0.062", "n.a."]),
        line(["Diegmann et al. (2026)", "Observable worker controls", "0.036", "n.a."]), r"    \midrule"]
for sample, label in [("raw", "No controls"), ("common", "Common-slope model"), ("Formal", "Formal workers"), ("Informal", "Informal workers")]:
    r = select(elasticities, sample=sample)
    rows.append(line(["Colombia (GEIH)", label, f'{float(r["estimate"]):.3f}{stars(r)}', f'({float(r["std.error"]):.3f})']))
table("regression_preferred_elasticity_table.tex", "Approximate firm-size elasticities with preferred controls",
      "tab:preferred-elasticities", "p{0.29\\textwidth}p{0.37\\textwidth}cc", ["Source", "Specification", "Elasticity", "S.E."], rows,
      r"Literature means reproduce Table 1 of \citet{DiegmannMullerSchoefer2026}. All Colombian estimates use the preferred sample and GEIH weights. "
      r"Controlled models include sex, age, age squared, education, occupational position, and sector-department-year fixed effects. "
      r"The common-slope model also includes formality. Formal and informal slopes come from a single interaction model, Equation~(\ref{eq:preferred-elasticity}). "
      r"Assigned sizes are 1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, and 150. Standard errors are clustered by sector-department. "
      r"* $p<0.10$, ** $p<0.05$, *** $p<0.01$.")

sensitivity = read("clustering_sensitivity")
rows = []
for group in ("Formal", "Informal"):
    if rows:
        rows.append(r"    \midrule")
    rows.append(r"    \multicolumn{6}{l}{\textit{" + group + r" workers}} \\")
    for model, label in [("sector_year", "Sector-year FE"), ("sector_dept_year", "Sector-department-year FE"), ("preferred", "+ Occupational position")]:
        sd = select(sensitivity, model=model, group=group, clustering="Sector-department")
        s = select(sensitivity, model=model, group=group, clustering="Sector")
        assert abs(float(sd["estimate"])-float(s["estimate"])) < 1e-12
        rows.append(line([label, f'{float(sd["premium"]):.1f}', f'{float(sd["std.error"]):.3f}', pvalue(sd), f'{float(s["std.error"]):.3f}', pvalue(s)]))
table("regression_preferred_clustering_table.tex", "Separating controls from clustering in the 101+/solo comparison",
      "tab:preferred-clustering-sensitivity", "lrrrrr",
      ["Controls", "Premium (\\%)", "S.E. (SD)", "$p$ (SD)", "S.E. (S)", "$p$ (S)"], rows,
      r"All rows use the same 5,268,375 observations, GEIH weights, size-by-formality interactions, and sex, age, age "
      r"squared, and education controls. The reference is solo work within each formality group. SD denotes "
      r"sector-department clustering and S denotes sector clustering. Standard errors are in log points. Two-sided tests "
      r"use 558 and 16 degrees of freedom, respectively. The last row in each panel is the preferred specification.", size="scriptsize")
rows = []
extension_sensitivity = read("extension_clustering_sensitivity")
for exercise, title in [("Endpoint change, 101+/solo", "Change in the 101+/solo log-wage gap, 2008--2025"), ("Elasticity", "Approximate firm-size elasticity")]:
    if rows:
        rows.append(r"    \midrule")
    rows.append(r"    \multicolumn{6}{l}{\textit{" + title + r"}} \\")
    for group in ("Formal", "Informal"):
        sd = select(extension_sensitivity, exercise=exercise, group=group, clustering="Sector-department")
        s = select(extension_sensitivity, exercise=exercise, group=group, clustering="Sector")
        assert abs(float(sd["estimate"])-float(s["estimate"])) < 1e-12
        rows.append(line([group, f'{float(sd["estimate"]):.3f}', f'{float(sd["std.error"]):.3f}', pvalue(sd), f'{float(s["std.error"]):.3f}', pvalue(s)]))
table("regression_preferred_extension_clustering_table.tex", "Clustering sensitivity of changes over time and elasticities",
      "tab:preferred-extension-clustering", "lrrrrr",
      ["Workers", "Estimate", "S.E. (SD)", "$p$ (SD)", "S.E. (S)", "$p$ (S)"], rows,
      r"SD denotes sector-department clustering and S denotes sector clustering. The first panel reports the 2025 minus "
      r"2008 change in the log-wage contrast from the joint endpoint model, not a percentage-point change. The second "
      r"panel reports slopes from Equation~(\ref{eq:preferred-elasticity}). Two-sided tests use 539 SD degrees of "
      r"freedom for the endpoint model, 558 for elasticities, and 16 for sector clustering in both models.")
print("Generated five preferred-model tables.")
