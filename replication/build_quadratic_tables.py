"""Produce appendix tables for the quadratic approximation, without changing older outputs."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/quadratic_output"
SECTIONS = ROOT / "Paper/sections"


def read(name):
    with (OUT / f"{name}.csv").open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def select(rows, **keys):
    found = [r for r in rows if all(r[k] == str(v) for k, v in keys.items())]
    assert len(found) == 1, keys
    return found[0]


def pvalue(row):
    p = float(row["p.value"])
    return "$<0.001$" if p < .001 else f"{p:.3f}"


def coefficient(row):
    p = float(row["p.value"])
    stars = "***" if p < .01 else "**" if p < .05 else "*" if p < .10 else ""
    return (r"\shortstack{" + f'{float(row["estimate"]):.4f}{stars}' +
            r"\\{\scriptsize (" + f'{float(row["std.error"]):.4f}' + r")}}")


def line(cells):
    return "    " + " & ".join(cells) + r" \\[0.25em]"


def table(filename, caption, label, columns, header, rows, notes):
    content = "\n".join([
        r"\begin{table}[htbp]", r"  \centering", "  \\caption{" + caption + "}",
        "  \\label{" + label + "}", r"  \small", "  \\begin{tabular}{" + columns + "}",
        r"    \toprule", line(header), r"    \midrule", *rows, r"    \bottomrule",
        r"  \end{tabular}", r"  \vspace{0.3em}", r"  \begin{minipage}{0.95\textwidth}",
        r"  \footnotesize", "  Notes: " + notes, r"  \end{minipage}", r"\end{table}", ""])
    (SECTIONS / filename).write_text(content, encoding="utf-8", newline="\n")


coefficients = read("coefficients")
predictions = read("category_predictions")
tests = read("restriction_tests")
rows = []
for term, label in [("linear", r"Log assigned size ($a_{1f}$)"), ("quadratic", r"Squared log assigned size ($a_{2f}$)")]:
    rows.append(line([label] + [coefficient(select(coefficients, top=150, group=g, term=term)) for g in ("Formal", "Informal")]))
rows.extend([r"    \midrule", line([r"Implied 101+/solo premium (\%)"] + [
    f'{float(select(predictions, top=150, group=g, size="101+")["premium"]):.1f}' for g in ("Formal", "Informal")])])
table("regression_preferred_quadratic_table.tex", "Quadratic size profiles with preferred controls",
      "tab:polynomial-size-profile", "lcc", ["Term", "Formal workers", "Informal workers"], rows,
      r"Both columns come from Equation~(\ref{eq:polynomial-size-profile}) on the preferred sample, with 101+ assigned "
      r"150 workers. The last row reports percentage premiums relative to solo work within each formality group. "
      r"Parentheses contain sector-department-clustered standard errors. * $p<0.10$, ** $p<0.05$, *** $p<0.01$.")

rows = []
for clustering in ("Sector-department", "Sector"):
    if rows:
        rows.append(r"    \midrule")
    rows.append(r"    \multicolumn{6}{l}{\textit{" + clustering + r" clustering}} \\")
    for top in (101, 150, 250):
        premiums = [f'{float(select(predictions, top=top, group=g, size="101+")["premium"]):.1f}' for g in ("Formal", "Informal")]
        pvalues = [pvalue(select(tests, top=top, group=g, clustering=clustering)) for g in ("Formal", "Informal", "Joint")]
        rows.append(line([str(top)] + premiums + pvalues))
table("regression_preferred_quadratic_sensitivity_table.tex", "Top-bin sensitivity and tests of the quadratic restriction",
      "tab:quadratic-preferred-sensitivity", "rrrrrr",
      [r"Size for 101+", r"Formal (\%)", r"Informal (\%)", r"$p_F$", r"$p_I$", r"$p_{Joint}$"], rows,
      r"Formal and informal percentages are the implied 101+/solo premiums from Equation~(\ref{eq:polynomial-size-profile}), re-estimated for "
      r"each assigned top-bin size. All other size assignments, observations, controls, and weights remain fixed. The "
      r"$p$-values test whether the unrestricted categorical profiles from Equation~(\ref{eq:main}) lie on the specified "
      r"quadratic. Wald tests use an $F_{q,G-1}$ reference distribution, with $q=6$ within each formality group and "
      r"$q=12$ jointly. There are 559 sector-department clusters or 17 sector clusters. "
      r"The value 150 is the baseline assignment, not an observed mean for 101+.")
print("Generated two preferred quadratic tables.")
