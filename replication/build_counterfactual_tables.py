"""Validate aggregate outputs and generate the three manuscript tables (stdlib only)."""

import csv
import math
import sys
from pathlib import Path

PAPER = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else PAPER / "replication/output"
SECTIONS = PAPER / "Paper/sections"
SCENARIOS = [
    ("formalize_same_size", "Informal to formal, same size", "Informal"),
    ("formal_to_101", "Formal workers to formal 101+", "Formal"),
    ("informal_to_101", "Informal workers to informal 101+", "Informal"),
    ("combined_formal_101", "All workers to formal 101+", "All"),
    ("informal_to_best", "Informal workers to informal 51--100", "Informal"),
    ("both_to_best_fixed_status", "Formal to 101+, informal to 51--100", "All"),
]


def read(name):
    with (OUT / name).open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


rows = read("scenario_results.csv")
key = lambda r: tuple(r[k] for k in ("scenario", "support", "method", "metric", "population"))
indexed = {key(r): r for r in rows}
assert len(indexed) == len(rows), "Duplicate scenario outputs"
groups = read("baseline_groups_2025.csv")
sample = {r["item"]: float(r["value"]) for r in read("sample_audit.csv")}
total_workers = sum(float(g["sum_w"]) for g in groups)
assert math.isclose(total_workers, sample["target_weight_sum"], rel_tol=1e-12)
profiles = {(r["size"], int(r["formal"])): float(r["log_profile"])
            for r in read("estimated_size_formality_profiles.csv")}
diagnostics = {r["scenario"]: r for r in read("support_diagnostics.csv")}
assert sum(int(g["n"]) for g in groups) == 341056
assert math.isclose(sum(float(g["worker_share_pct"]) for g in groups), 100, abs_tol=1e-9)
checks = read("coefficient_replication_check.csv")
assert len(checks) == 8
assert max(abs(float(v)) for r in checks for k, v in r.items() if k != "size") < 1e-7


def result(scenario, population="all", method="predicted_common_smear", support="unrestricted"):
    return indexed[scenario, support, method, "weekly", population]


def gain(scenario, **kwargs):
    return float(result(scenario, **kwargs)["gain_pct"])


def destination(size, formal, scenario):
    if scenario == "formalize_same_size":
        return size, 1
    if scenario == "formal_to_101":
        return ("101+", 1) if formal else (size, formal)
    if scenario == "informal_to_101":
        return (size, formal) if formal else ("101+", 0)
    if scenario == "combined_formal_101":
        return "101+", 1
    best = max((s for s, f in profiles if f == formal), key=lambda s: profiles[s, formal])
    if scenario == "informal_to_best":
        return (size, formal) if formal else (best, formal)
    return best, formal


# Independently reconstruct totals from 18 origin groups, not from the R transition helper.
validation = []
reassigned_workers = {}
for scenario, _, target in SCENARIOS:
    reassigned_workers[scenario] = sum(
        float(g["sum_w"]) for g in groups
        if destination(g["tamano_empresa"], int(g["formal"]), scenario)
        != (g["tamano_empresa"], int(g["formal"]))
    )
    moved_share = 100 * reassigned_workers[scenario] / total_workers
    assert math.isclose(moved_share, float(result(scenario)["moved_worker_share_pct"]), rel_tol=1e-12)
    assert math.isclose(moved_share, float(diagnostics[scenario]["intended_move_share_pct"]), rel_tol=1e-12)
    for method, field in (("predicted_common_smear", "weekly_predicted"),
                          ("observed_residual_preserved", "weekly_observed")):
        for population in ("all", "target_group", "movers"):
            baseline = change = 0.0
            for g in groups:
                size, formal = g["tamano_empresa"], int(g["formal"])
                dest = destination(size, formal, scenario)
                if population == "movers" and dest == (size, formal):
                    continue
                if population == "target_group" and target != "All":
                    if formal != (1 if target == "Formal" else 0):
                        continue
                mass = float(g["sum_w"]) * float(g[field])
                delta = profiles[dest] - profiles[size, formal]
                baseline += mass
                change += mass * math.expm1(delta)
            independent = 100 * change / baseline
            error = independent - gain(scenario, population=population, method=method)
            assert abs(error) < 1e-9, (scenario, population, method, error)
            validation.append({"scenario": scenario, "population": population, "method": method,
                               "independent_gain_pct": independent, "error_pp": error})
for row in rows:
    implied = 100 * (float(row["counterfactual_mean"]) / float(row["baseline_mean"]) - 1)
    assert abs(implied - float(row["gain_pct"])) < 1e-8
assert math.isclose(gain("both_to_best_fixed_status"),
                    gain("formal_to_101") + gain("informal_to_best"), abs_tol=1e-9)

with (OUT / "independent_arithmetic_checks.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(validation[0]))
    writer.writeheader()
    writer.writerows(validation)


def table(caption, label, columns, body, notes, placement="htbp"):
    return rf"""% Generated by replication/build_counterfactual_tables.py.
\begin{{table}}[{placement}]
  \centering
  \caption{{{caption}}}
  \label{{{label}}}
  \small
  \begin{{tabular}}{{{columns}}}
    \toprule
{body}
    \bottomrule
  \end{{tabular}}
  \vspace{{0.4em}}
  \begin{{minipage}}{{0.97\textwidth}}
  \footnotesize
  Notes: {notes}
  \end{{minipage}}
\end{{table}}
"""


body = [r"    Scenario & \shortstack[l]{Initial\\group} & \shortstack[r]{Workers\\reassigned\\(millions)} & \shortstack[r]{Group total\\(\%)} & \shortstack[r]{Reassigned\\mean (\%)} & \shortstack[r]{All-worker\\total (\%)} \\", r"    \midrule"]
for scenario, title, target in SCENARIOS[:4]:
    if scenario == "combined_formal_101":
        body.append(r"    \midrule")
    body.append(f"    {title} & {target} & {reassigned_workers[scenario] / 1e6:.2f} "
                f"& {gain(scenario, population='target_group'):.1f} "
                f"& {gain(scenario, population='movers'):.1f} & {gain(scenario):.1f} " + r"\\[0.5em]")
main = table(
    "Illustrative changes in predicted labor income, 2025",
    "tab:income-counterfactuals-2025", r"@{}>{\raggedright\arraybackslash}p{0.27\textwidth}lrrrr@{}", "\n".join(body),
    r"Income columns report percentage changes in predicted weekly labor income from Equation~(\ref{eq:income-counterfactual}), "
    r"using the pooled coefficients from Equation~(\ref{eq:main}). "
    f"The 2025 sample represents {total_workers / 1e6:.1f} million workers. "
    r"Group totals include everyone initially in the indicated group. Reassigned means use only workers whose "
    r"size or formality changes. The all-worker total includes the entire 2025 sample. In the last row, both "
    r"formal and informal workers are assigned to formal 101+ employment. Workers already there retain their baseline income.")
(SECTIONS / "income_counterfactuals_2025_table.tex").write_text(main, encoding="utf-8")

body = [r"    Scenario & Predicted baseline & Observed baseline \\",
        r"    & (\%) & (\%) \\", r"    \midrule"]
for i, (scenario, title, _) in enumerate(SCENARIOS):
    if i == 4:
        body += [r"    \midrule", r"    \multicolumn{3}{l}{\textit{Destinations selected from the estimated profiles}} \\"]
    alternate = gain(scenario, method="observed_residual_preserved")
    body.append(f"    {title} & {gain(scenario):.1f} & {alternate:.1f} " + r"\\[0.4em]")
sensitivity = table(
    "Income scenarios with alternative baselines and destinations",
    "tab:income-counterfactual-sensitivity", r">{\raggedright\arraybackslash}p{0.52\textwidth}cc", "\n".join(body),
    r"Percentage changes in total weekly labor income for the entire 2025 sample. The predicted baseline uses "
    r"Equation~(\ref{eq:income-counterfactual}). The observed baseline rescales observed income by the same estimated "
    r"wage ratios, preserving log residuals. Both use pooled coefficients from Equation~(\ref{eq:main}). In the last two "
    r"rows, destinations maximize the estimated size component within each formality group, including moves from "
    r"informal 101+ to informal 51--100.", "p")
(SECTIONS / "income_counterfactual_sensitivity_table.tex").write_text(sensitivity, encoding="utf-8")

body = [r"    \multicolumn{5}{l}{\textit{A. Intended moves and absent destination cells (\%)}} \\",
        r"    \midrule",
        r"    Scenario & \shortstack{Intended\\movers} & \multicolumn{2}{c}{\shortstack{Absent destination\\in 2025}} & \shortstack{Absent\\in pooled} \\",
        r"    \midrule"]
for scenario, title, _ in SCENARIOS:
    d = diagnostics[scenario]
    title = title.replace("Formal workers to formal", "Formal to").replace("Informal workers to informal", "Informal to").replace("All workers to", "All to")
    body.append(f"    {title} & {float(d['intended_move_share_pct']):.1f} & "
                + rf"\multicolumn{{2}}{{c}}{{{float(d['destination_absent_2025_pct_of_intended']):.1f}}}"
                + f" & {float(d['destination_absent_pooled_pct_of_intended']):.1f} " + r"\\[0.3em]")
body += [r"    \midrule", r"    \multicolumn{5}{l}{\textit{B. Change in total predicted income with destination screens (\%)}} \\",
         r"    \midrule", r"    Scenario & No screen & \shortstack{Pooled\\$n\geq30$} & \shortstack{2025\\$n\geq10$} & \shortstack{2025\\$n\geq30$} \\", r"    \midrule"]
for scenario, title, _ in SCENARIOS:
    title = title.replace("Formal workers to formal", "Formal to").replace("Informal workers to informal", "Informal to").replace("All workers to", "All to")
    entries = []
    for support in ("unrestricted", "pooled_n30", "target_n10", "target_n30"):
        r = result(scenario, support=support)
        value = float(r["gain_pct"])
        entry = r"\textit{None}" if float(r["moved_worker_share_pct"]) == 0 else (r"$<0.1$" if 0 < value < 0.05 else f"{value:.1f}")
        entries.append(entry)
    body.append(f"    {title} & " + " & ".join(entries) + r"\\[0.3em]")
support = table(
    "Observed destination groups and sensitivity to extrapolation, 2025",
    "tab:income-counterfactual-support",
    r">{\raggedright\arraybackslash}p{0.40\textwidth}cccc",
    "\n".join(body),
    r"Destination cells are defined by sector, department, occupational position, size, and formality. Panel A reports "
    r"intended movers as a percentage of all workers. The absent-destination columns instead use intended movers as "
    r"their denominator. Pooled counts use all estimation years. Panel B permits a move only when its destination "
    r"meets the stated unweighted observation count. Otherwise the worker stays at origin. The all-worker income "
    r"denominator is unchanged. \textit{None} means that no intended move qualifies. For the joint "
    r"selected-destination scenario, the 2025 $n\geq30$ column contains only formal moves.", "p")
(SECTIONS / "income_counterfactual_support_table.tex").write_text(support, encoding="utf-8")
print(f"Validated {len(validation)} aggregate changes and generated three tables.")
print(f"Workers represented in 2025: {total_workers:,.0f}")
for scenario, title, _ in SCENARIOS[:4]:
    print(f"{title}: {reassigned_workers[scenario]:,.0f} workers reassigned")
print(f"Maximum independent error: {max(abs(r['error_pp']) for r in validation):.3g} pp")
