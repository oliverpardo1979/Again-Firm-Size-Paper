"""Export the paper's current tables to Beamer without copying estimates by hand.

Run after compiling main.tex, then compile presentacion_javeriana.tex.
Generated TeX is committed, so Overleaf does not need Python.
"""

import csv
import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Slides/generated"
SOURCES = {}


def group(text, start):
    """Read a balanced TeX brace group, including nested column specifications."""
    assert text[start] == "{"
    depth = 1
    end = start + 1
    while depth:
        if text[end] in "{}" and text[end - 1] != "\\":
            depth += 1 if text[end] == "{" else -1
        end += 1
    return text[start + 1:end - 1], end


def command(text, name):
    match = re.search(r"\\" + name + r"\s*\{", text)
    return group(text, match.end() - 1)[0] if match else ""


def expand(path):
    text = path.read_text(encoding="utf-8-sig")
    text = re.sub(r"(?<!\\)%[^\n]*", "", text)
    for label in re.findall(r"\\label\{([^}]+)\}", text):
        SOURCES[label] = path.relative_to(ROOT).as_posix()
    return re.sub(
        r"\\input\{([^}]+)\}",
        lambda m: expand(ROOT / (m[1] if m[1].endswith(".tex") else m[1] + ".tex")),
        text,
    )


def rows(text):
    """Split only top-level row endings, leaving shortstack cells intact."""
    result, start, depth, i = [], 0, 0, 0
    while i < len(text):
        if text.startswith(r"\\", i) and depth == 0:
            end = i + 2
            if end < len(text) and text[end] == "[":
                end = text.index("]", end) + 1
            result.append(text[start:i].strip())
            start = end
            i = end
            continue
        if text[i] in "{}" and (i == 0 or text[i - 1] != "\\"):
            depth += 1 if text[i] == "{" else -1
        i += 1
    tail = text[start:].strip()
    if tail:
        result.append(tail)
    return result


def small_se(text):
    return re.sub(r"\{\\scriptsize\s+\(([0-9.]+)\)\}", r"\\sereg{\1}", text)


def merge_se_rows(items):
    merged = []
    for row in items:
        if not row.strip():
            continue
        cells = row.split("&")
        if (merged and not cells[0].strip()
                and all(not c.strip() or re.fullmatch(r"\([\d.]+\)", c.strip()) for c in cells[1:])):
            previous = merged.pop().split("&")
            assert len(previous) == len(cells), (previous, cells)
            merged.append(" & ".join(
                p.strip() + (" " + r"\sereg{" + c.strip()[1:-1] + "}" if c.strip() else "")
                for p, c in zip(previous, cells)
            ))
        else:
            merged.append(small_se(row))
    return merged


def table_parts(block):
    start = block.index(r"\begin{tabular}") + len(r"\begin{tabular}")
    spec, end = group(block, start)
    body = block[end:block.index(r"\end{tabular}", end)].strip()
    head, body = body.split(r"\midrule", 1)
    body = body.replace(r"\bottomrule", "").strip()
    # Within-formality tables repeat the same header and controls on both panels.
    panels = re.split(r"\\midrule\s*(?=\\multicolumn\{\d+\}\{l\}\{\\textit\{(?:In)?[Ff]ormal workers)", body)
    if len(panels) == 2:
        footer = ""
        if r"\midrule" in panels[1]:
            panels[1], footer = panels[1].split(r"\midrule", 1)
            footer = r"\midrule" + footer
        result = [(head, p + footer) for p in panels]
    elif "A. Intended moves" in head:
        first, second = body.split(r"\multicolumn{5}{l}{\textit{B.", 1)
        first = re.sub(r"\\midrule\s*$", "", first)
        second = r"\toprule\multicolumn{5}{l}{\textit{B." + second
        # Panel B has its own column definitions, not Panel A's header.
        cut = second.index(r"\midrule", second.index(r"\midrule") + 1)
        result = [(head, first), (second[:cut], second[cut + len(r"\midrule"):])]
    else:
        items = merge_se_rows(rows(body))
        if any(label in block for label in (
            "tab:preferred-clustering-comparison", "tab:preferred-wild-bootstrap"
        )):
            # Keep each inference panel together, including its heading.
            groups = []
            for item in items:
                if re.search(r"\\multicolumn\{\d+\}\{l\}\{\\textit\{[A-D]\.", item):
                    groups.append([])
                groups[-1].append(item)
            chunks = [[]]
            for panel in groups:
                if chunks[-1] and len(chunks[-1]) + len(panel) > 13:
                    chunks.append([])
                chunks[-1].extend(panel)
        elif "descriptive-wage-gaps-2025" in block:
            chunks = [items[:8], items[8:16], items[16:]]
            chunks[2][0] = "Activity " + chunks[2][0]
        elif 13 < len(items) <= 18 and any(r"\midrule" in item for item in items[7:]):
            cut = max(i for i, item in enumerate(items) if r"\midrule" in item)
            chunks = [items[:cut], items[cut:]]
        else:
            chunks = [items[i:i + 13] for i in range(0, len(items), 13)]
        result = [(head, " \\\\\n".join(chunk) + r"\\") for chunk in chunks]
    output = []
    for header, part in result:
        part = " \\\\\n".join(merge_se_rows(rows(part))) + r"\\"
        part = re.sub(r"^(?:\s*\\midrule)+", "", part)
        output.append(r"\begin{tabular}{" + spec + "}\n" + header
                      + r"\midrule" + "\n" + part + "\n"
                      + r"\bottomrule\end{tabular}")
    return output


def slide_notes(label, original):
    stars = r" SEs in parentheses. * $p<0.10$, ** $p<0.05$, *** $p<0.01$."
    preferred_bases = {
        "tab:firm-size-local-geography-formality-robustness": "solo",
        "tab:firm-size-local-geography-formality-robustness-101-reference": "101+",
        "tab:firm-size-local-geography-formality-robustness-11-19-reference": "11--19",
    }
    common_bases = {
        "tab:firm-size-local-geography-robustness": "solo",
        "tab:firm-size-local-geography-robustness-101-reference": "101+",
        "tab:firm-size-local-geography-robustness-11-19-reference": "11--19",
    }
    if label in preferred_bases:
        base = preferred_bases[label]
        return ("Within-formality log contrasts relative to " + base + " workers. "
                r"All columns include worker controls and GEIH weights. FE: (1) $s\times t$, "
                r"(2) $s\times t$ and $d\times t$, (3)--(4) $s\times d\times t$. "
                "Column (4) adds occupational position and is preferred. "
                "SEs cluster by sector-department." + stars)
    if label == "tab:salaried-robustness":
        return (r"Main rows are log contrasts relative to 11--19 workers within formality. "
                r"Summary premiums instead use solo work. Same preferred controls and weights. "
                r"Salaried workers include private, government, and domestic employees and day laborers. "
                r"SEs cluster by sector-department (559 full-sample, 555 salaried clusters). "
                r"Equality tests use the full covariance matrix." + stars)
    if label in common_bases:
        base = common_bases[label]
        return ("Common-premium model with " + base + " as the reference. "
                "All columns include worker characteristics and formality. "
                r"FE: (1) $s\times t$, (2) $s\times t$ and $d\times t$, "
                r"(3)--(4) $s\times d\times t$. "
                "Column (4) adds occupational position. SEs cluster by sector-department." + stars)
    return original


def export_summary_tables():
    """Use saved estimates for the main-talk bootstrap and mover comparisons."""
    bootstrap_path = ROOT / "replication/inference_audit_output/wild_bootstrap.csv"
    scenario_path = ROOT / "replication/output/scenario_results.csv"
    sample_path = ROOT / "replication/output/sample_audit.csv"
    with bootstrap_path.open(encoding="utf-8", newline="") as stream:
        bootstrap = {(r["model"], r["contrast"], r["clustering"]): r
                     for r in csv.DictReader(stream)}
    pvalue = lambda value: r"$<0.001$" if float(value) < 0.001 else f"{float(value):.3f}"
    lines = [r"\begin{tabular}{lrrr}", r"\toprule",
             r"Contrast & Premium (\%) & $p$ (sector) & $p$ (two-way) \\", r"\midrule"]
    for contrast in ("Formal 101+/solo", "Informal 101+/solo",
                     "Formal 101+/11-19", "Informal 101+/11-19"):
        sector = bootstrap[("preferred", contrast, "Sector")]
        two_way = bootstrap[("preferred", contrast, "Two-way sector + department")]
        premium = 100 * math.expm1(float(sector["estimate"]))
        label = contrast.replace("11-19", "11--19")
        lines.append(f"{label} & {premium:.1f} & {pvalue(sector['p_wild'])}"
                     f" & {pvalue(two_way['p_wild'])}" + r" \\")
    lines.append(r"\bottomrule\end{tabular}")
    (OUT / "bootstrap_summary.tex").write_text("\n".join(lines) + "\n", encoding="utf-8")

    with scenario_path.open(encoding="utf-8", newline="") as stream:
        scenarios = {(r["scenario"], r["population"]): r for r in csv.DictReader(stream)
                     if r["support"] == "unrestricted" and r["metric"] == "weekly"
                     and r["method"] == "predicted_common_smear"}
    with sample_path.open(encoding="utf-8", newline="") as stream:
        sample = {r["item"]: float(r["value"]) for r in csv.DictReader(stream)}
    workers_millions = sample["target_weight_sum"] / 1e6
    lines = [rf"{{\small Workers represented in 2025: {workers_millions:.1f} million.\par}}",
             r"\vspace{0.2cm}",
             r"\begin{tabular}{p{0.36\textwidth}rrr}", r"\toprule",
             r"Assignment & \shortstack{Workers\\reassigned\\(millions)}"
             r" & \shortstack{Reassigned workers\\Mean income\\gain (\%)}"
             r" & \shortstack{All workers\\Total income\\gain (\%)} \\", r"\midrule"]
    for scenario, label in (
        ("formalize_same_size", "Informal to formal, same size"),
        ("formal_to_101", "Formal to formal 101+"),
        ("informal_to_101", "Informal to informal 101+"),
        ("combined_formal_101", "All workers to formal 101+"),
    ):
        if scenario == "combined_formal_101":
            lines.append(r"\midrule")
        movers = float(scenarios[(scenario, "movers")]["gain_pct"])
        all_workers = float(scenarios[(scenario, "all")]["gain_pct"])
        moved_share = float(scenarios[(scenario, "all")]["moved_worker_share_pct"])
        moved_millions = workers_millions * moved_share / 100
        lines.append(f"{label} & {moved_millions:.2f} & {movers:.1f} & {all_workers:.1f}" + r" \\")
    lines.append(r"\bottomrule\end{tabular}")
    (OUT / "income_movers.tex").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (bootstrap_path, scenario_path, sample_path)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    expanded = expand(ROOT / "main.tex")
    aux = (ROOT / "build/main.aux").read_text(encoding="utf-8")
    refs = dict(re.findall(r"\\newlabel\{([^}]+)\}\{\{([^}]+)\}", aux))
    citations = {"DiegmannMullerSchoefer2026": "Diegmann et al. (2026)"}
    reference_tex = [r"\newcommand{\paperref}[1]{\csname paperref@#1\endcsname}"]
    reference_tex += [r"\expandafter\def\csname paperref@" + key + r"\endcsname{" + value + "}"
                      for key, value in refs.items()]
    (OUT / "paper_references.tex").write_text("\n".join(reference_tex) + "\n", encoding="utf-8")
    aliases = {
        "tab:firm-size-wage-premium-regressions": "sequential_controls.tex",
        "tab:firm-size-local-geography-robustness": "common_geography.tex",
        "tab:preferred-elasticities": "preferred_elasticities.tex",
    }
    expected_files = set()

    def resolve(text):
        text = re.sub(r"\\ref\{([^}]+)\}", lambda m: refs[m[1]], text)
        return re.sub(r"\\cite[tp]\{([^}]+)\}", lambda m: citations[m[1]], text)

    entries, frames = [], []
    for number, match in enumerate(re.finditer(r"\\begin\{table\}.*?\\end\{table\}", expanded, re.S), 1):
        block = match[0]
        label, caption = command(block, "label"), command(block, "caption")
        assert str(number) == refs[label], (number, label, refs[label])
        parts = table_parts(block)
        if label in aliases:
            assert len(parts) == 1, label
            (OUT / aliases[label]).write_text(resolve(parts[0]) + "\n", encoding="utf-8")
        notes_match = re.search(r"Notes:\s*(.*?)\\end\{minipage\}", block, re.S)
        notes = resolve(notes_match[1].strip()) if notes_match else ""
        entry = {"number": number, "label": label, "source": SOURCES[label],
                 "sha256": hashlib.sha256((ROOT / SOURCES[label]).read_bytes()).hexdigest(),
                 "parts": len(parts)}
        entries.append(entry)
        for i, tabular in enumerate(parts, 1):
            filename = f"table_{number:02d}_{i}.tex"
            expected_files.add(filename)
            (OUT / filename).write_text("% Generated from " + SOURCES[label] + "\n" + resolve(tabular) + "\n", encoding="utf-8")
            suffix = f" ({i}/{len(parts)})" if len(parts) > 1 else ""
            comparison = "Comparison specification. " if label.startswith((
                "tab:firm-size-wage-premium-regressions-", "tab:firm-size-local-geography-robustness-",
                "tab:formality-interaction-coefficients", "tab:firm-size-premium-trend-test"
            )) or label in {"tab:formal-101-contrasts", "tab:formal-wage-gap-by-size",
                           "tab:firm-size-elasticity-benchmark"} else ""
            frame = (r"\begin{frame}{Paper Table " + str(number) + suffix + "}\n"
                     + r"\begin{minipage}{\textwidth}\small\textbf{" + resolve(caption) + "}"
                     + r"\end{minipage}\par\vspace{0.15cm}" + "\n"
                     + r"\centering\begingroup\fontsize{8.5}{10}\selectfont" + "\n"
                     + r"\setlength{\tabcolsep}{4pt}\renewcommand{\arraystretch}{1.06}" + "\n"
                     + r"\begin{adjustbox}{max width=\textwidth,max totalheight=0.64\textheight}" + "\n"
                     + r"\input{Slides/generated/" + filename + "}\n"
                     + r"\end{adjustbox}\endgroup\par\vspace{0.10cm}" + "\n"
                     + r"{\fontsize{6.5}{7.5}\selectfont\raggedright " + comparison + slide_notes(label, notes) + r"\par}" + "\n"
                     + r"\note{" + notes + "}\n"
                     + r"\end{frame}" + "\n")
            frames.append(frame)

    figures = []
    for number, match in enumerate(re.finditer(r"\\begin\{figure\}.*?\\end\{figure\}", expanded, re.S), 1):
        label = command(match[0], "label")
        name = re.search(r"\\includegraphics(?:\[[^]]*\])?\{([^}]+)\}", match[0])[1]
        name = name.replace(r"\figurelang", "en")
        assert str(number) == refs[label]
        assert (ROOT / "Paper/figures" / name).exists(), name
        figures.append({"number": number, "label": label, "file": name})
    (OUT / "all_paper_tables.tex").write_text("% Generated by replication/build_presentation_assets.py\n" + "\n".join(frames), encoding="utf-8")
    # Remove only obsolete files owned by this exporter after table renumbering.
    for stale in OUT.glob("table_[0-9][0-9]_*.tex"):
        if stale.name not in expected_files:
            assert stale.resolve().parent == OUT.resolve()
            assert stale.read_text(encoding="utf-8").startswith("% Generated from ")
            stale.unlink()
    summary_sources = export_summary_tables()
    (OUT / "coverage.json").write_text(json.dumps({
        "tables": entries, "figures": figures, "summary_sources": summary_sources
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {len(entries)} paper tables to {len(frames)} backup frames.")
    print(json.dumps(figures, indent=2))


if __name__ == "__main__":
    main()
