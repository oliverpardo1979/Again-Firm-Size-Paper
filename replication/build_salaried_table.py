"""Compare the corrected preferred model with the salaried-only specification."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/salaried_output"


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


models = {r["sample"]: r for r in read("models")}
rows = {(r["sample"], r["group"], r["size"]): r for r in read("contrasts")
        if r["reference"] == "11-19" and r["clustering"] == "Sector-department"}
columns = [(s, g) for s in ("All", "Salaried") for g in ("Informal", "Formal")]
lines = [r"\begin{table}[htbp]", r"  \centering",
         r"  \caption{Firm-size premiums in the full and salaried-only samples}",
         r"  \label{tab:salaried-robustness}", r"  \small",
         r"  \begin{tabular}{lrrrr}", r"    \toprule",
         r"    & \multicolumn{2}{c}{All workers} & \multicolumn{2}{c}{Salaried workers} \\",
         r"    \cmidrule(lr){2-3}\cmidrule(lr){4-5}",
         r"    Firm size & Informal & Formal & Informal & Formal \\", r"    \midrule"]
for size in ("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"):
    if size == "11-19":
        lines.append(r"    11--19 & Reference & Reference & Reference & Reference \\")
        continue
    cells, ses = [], []
    for sample, group in columns:
        r = rows[sample, group, size]
        p = float(r["p.value"])
        stars = "***" if p < .01 else "**" if p < .05 else "*" if p < .1 else ""
        cells.append(f'{float(r["estimate"]):.3f}{stars}')
        ses.append(f'({float(r["std.error"]):.3f})')
    lines.extend(["    " + " & ".join([size.replace("-", "--"), *cells]) + r" \\",
                  "    " + " & ".join(["", *ses]) + r" \\"])
solo = {(r["sample"], r["group"]): r for r in read("contrasts")
        if r["reference"] == "Solo" and r["size"] == "101+" and r["clustering"] == "Sector-department"}
lines.extend([r"    \midrule",
              "    101+/solo premium (\\%) & " + " & ".join(f'{float(solo[s, g]["premium"]):.1f}' for s, g in columns) + r" \\",
              "    Observations & \\multicolumn{2}{c}{" + f'{int(models["All"]["n"]):,}' +
              "} & \\multicolumn{2}{c}{" + f'{int(models["Salaried"]["n"]):,}' + r"} \\",
              r"    \bottomrule", r"  \end{tabular}", r"  \vspace{0.3em}",
              r"  \begin{minipage}{0.95\textwidth}", r"  \footnotesize",
              r"  Notes: The main rows are log-wage contrasts relative to workers in firms with 11--19 workers within the same formality group. "
              r"The summary row instead compares 101+ with solo work in percent within each group. "
              r"Each pair of columns comes from one size-by-formality regression. Salaried workers comprise private-sector employees, "
              r"government employees, domestic workers, and day laborers. Both models include sex, age, age squared, education, "
              r"occupational-position controls, and sector-department-year fixed effects, and use GEIH expansion weights. "
              r"Singleton fixed-effect cells are removed separately in each sample. Standard errors in parentheses are clustered "
              r"by sector-department. Two-sided tests use each sample's cluster count. Percent gaps are $100[\exp(b)-1]$. "
              r"* $p<0.10$, ** $p<0.05$, *** $p<0.01$.",
              r"  \end{minipage}", r"\end{table}", ""])
(ROOT / "Paper/sections/regression_salaried_robustness_table.tex").write_text("\n".join(lines), encoding="utf-8", newline="\n")
print("Generated salaried-only robustness table.")
