"""Compare the corrected preferred model with the salaried-only specification."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/salaried_output"


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


models = {r["sample"]: r for r in read("models")}
tests = {(r["sample"], r["test"]): r for r in read("formality_equality_tests")
         if r["clustering"] == "Sector-department"}


def test_row(label, test):
    cells = []
    for sample in ("All", "Salaried"):
        p = float(tests[sample, test]["p.value"])
        display = "$<0.001$" if p < .001 else f"{p:.3f}"
        cells.append(r"\multicolumn{2}{c}{" + display + "}")
    return "    " + " & ".join([label, *cells]) + r" \\"

rows = {(r["sample"], r["group"], r["size"]): r for r in read("contrasts")
        if r["reference"] == "11-19" and r["clustering"] == "Sector-department"}
columns = [(s, g) for s in ("All", "Salaried") for g in ("Informal", "Formal")]
lines = [r"\begin{table}[!htbp]", r"  \centering",
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
solo = {(r["sample"], r["group"], r["size"]): r for r in read("contrasts")
        if r["reference"] == "Solo" and r["clustering"] == "Sector-department"}
lines.append(r"    \midrule")
for size in ("11-19", "101+"):
    lines.append("    " + size.replace("-", "--") + "/solo premium (\\%) & " +
                 " & ".join(f'{float(solo[s, g, size]["premium"]):.1f}' for s, g in columns) + r" \\")
lines.extend([test_row(r"Equal 101+/solo premiums: $p$", "101+/solo equality"),
              test_row(r"Equal size profiles: $p$", "Joint profile equality"),
              "    Observations & \\multicolumn{2}{c}{" + f'{int(models["All"]["n"]):,}' +
              "} & \\multicolumn{2}{c}{" + f'{int(models["Salaried"]["n"]):,}' + r"} \\",
              r"    \bottomrule", r"  \end{tabular}", r"  \vspace{0.3em}",
              r"  \begin{minipage}{0.95\textwidth}", r"  \footnotesize",
              r"  Notes: Main rows report within-formality log-wage contrasts relative to 11--19 workers. "
              r"Summary premiums use solo work as the reference and equal $100[\exp(b)-1]$. "
              r"Each column pair comes from one size-by-formality regression with sex, age, age squared, education, "
              r"occupational-position controls, sector-department-year fixed effects, and GEIH expansion weights. "
              r"Salaried workers comprise private, government, and domestic employees and day laborers. "
              r"The restricted sample excludes 66 additional singleton cells. Standard errors in parentheses use "
              r"sector-department clustering, with $G=559$ clusters in the full sample and $G=555$ among employees. "
              r"Equality tests compare the formal and informal 101+/solo log contrasts (two-sided $t$ test) "
              r"and jointly compare all eight size contrasts relative to solo work (Wald $F$ test with eight numerator "
              r"degrees of freedom). Both use the full coefficient covariance and $G-1$ denominator degrees of freedom. "
              r"* $p<0.10$, ** $p<0.05$, *** $p<0.01$.",
              r"  \end{minipage}", r"\end{table}", ""])
(ROOT / "Paper/sections/regression_salaried_robustness_table.tex").write_text("\n".join(lines), encoding="utf-8", newline="\n")
print("Generated salaried-only robustness table.")
