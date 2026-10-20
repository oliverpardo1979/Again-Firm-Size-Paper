"""Check presentation coverage, selected regression rows, and PDF layout logs."""

import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path

from build_presentation_assets import ROOT, expand, group, merge_se_rows, rows


def read(path):
    return path.read_text(encoding="utf-8-sig")


def table_body(text):
    start = text.index(r"\begin{tabular}") + len(r"\begin{tabular}")
    _, end = group(text, start)
    return text[end:text.index(r"\end{tabular}", end)]


def frame(text, title):
    start = text.index(r"\begin{frame}{" + title + "}")
    return text[start:text.index(r"\end{frame}", start)]


def numeric(cell):
    # Compare both coefficient and standard error, including significance stars.
    return re.findall(r"-?\d+(?:\.\d+)?\*{0,3}", cell)


def selected_rows(text):
    result = {}
    for row in merge_se_rows(rows(table_body(text))):
        row = re.sub(r"\\(?:toprule|midrule|bottomrule|addlinespace)", "", row).strip()
        cells = row.split("&")
        key = cells[0].strip().replace("--", "-").replace("Firm size: ", "")
        if key in ("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"):
            result[key] = [numeric(c) for c in cells[1:]]
    return result


def validate():
    manifest = json.loads(read(ROOT / "Slides/generated/coverage.json"))
    main = read(ROOT / "presentacion_javeriana.tex")
    assert r"\newcommand{\source}[1]{}" in main, "Source footers must stay hidden."
    results = read(ROOT / "Slides/main_results.tex")
    backup = read(ROOT / "Slides/backup_figures.tex")
    details = read(ROOT / "Slides/backup_talk_details.tex")
    all_slides = main + results + details + backup
    main_body = main.split(r"\begin{document}", 1)[1].split(r"\appendix", 1)[0]
    main_body = main_body.replace(r"\input{Slides/main_results}", results)
    main_body = re.sub(r"(?m)^\s*%.*$", "", main_body)
    main_slide_count = main_body.count(r"\begin{frame}")
    assert 0 < main_slide_count <= 20, "The main talk must contain at most 20 slides."
    for title in ("Endpoint Changes Differ by Formality",
                  "What Would Labor Income Be under Worker Reallocation?"):
        assert r"%\begin{frame}{" + title + "}" in results, title
        assert r"\begin{frame}{" + title + "}" not in main_body, title
    assert r"\begin{frame}{Illustrative Income Changes in 2025}" in main_body
    elasticity_title = r"\begin{frame}{Benchmarking the Elasticities}"
    assert elasticity_title not in main_body, "Elasticity benchmarks belong in the appendix."
    assert details.count(elasticity_title) == 1
    assert details.index("Why Estimate an Approximate Elasticity?") < details.index(elasticity_title)
    assert r"\sectionframe" not in main_body, "Section dividers belong in the appendix."
    assert r"\input{Slides/backup_talk_details}" in main.split(r"\appendix", 1)[1]
    for title in ("Roadmap", "Main Results", "Why Firm Size Matters", "Data", "Discussion"):
        assert r"\begin{frame}{" + title + "}" in all_slides, title
    for source, digest in manifest["summary_sources"].items():
        assert hashlib.sha256((ROOT / source).read_bytes()).hexdigest() == digest, source
    references = read(ROOT / "Slides/generated/paper_references.tex")
    for label in re.findall(r"\\paperref\{([^}]+)\}", all_slides):
        assert "paperref@" + label + r"\endcsname" in references, label
    for figure in manifest["figures"]:
        assert figure["file"] in all_slides, figure
    for entry in manifest["tables"]:
        source = ROOT / entry["source"]
        assert hashlib.sha256(source.read_bytes()).hexdigest() == entry["sha256"], source
        generated = "\n".join(read(ROOT / f"Slides/generated/table_{entry['number']:02d}_{i}.tex")
                              for i in range(1, entry["parts"] + 1))
        # Every numerical token in the canonical tabular must survive pagination.
        strip_spacing = lambda text: re.sub(r"\[[\d.]+(?:em|ex|pt|cm)\]", "", text)
        original = set(numeric(strip_spacing(table_body(read(source)))))
        actual = set(numeric(strip_spacing(generated)))
        assert original <= actual, (source, original - actual)

    bootstrap_table = read(ROOT / "Slides/generated/bootstrap_summary.tex")
    with (ROOT / "replication/inference_audit_output/wild_bootstrap.csv").open(
        encoding="utf-8", newline=""
    ) as stream:
        bootstrap = {(r["model"], r["contrast"], r["clustering"]): r
                     for r in csv.DictReader(stream)}
    for contrast in ("Formal 101+/solo", "Informal 101+/solo",
                     "Formal 101+/11-19", "Informal 101+/11-19"):
        sector = bootstrap[("preferred", contrast, "Sector")]
        two_way = bootstrap[("preferred", contrast, "Two-way sector + department")]
        premium = 100 * math.expm1(float(sector["estimate"]))
        cells = [contrast.replace("11-19", "11--19"), f"{premium:.1f}"]
        for row in (sector, two_way):
            p = float(row["p_wild"])
            cells.append(r"$<0.001$" if p < 0.001 else f"{p:.3f}")
        assert " & ".join(cells) + r" \\" in bootstrap_table, contrast

    income_table = read(ROOT / "Slides/generated/income_movers.tex")
    assert r"Allocation & \shortstack{Workers" in income_table
    assert r"Reassigned workers\\Mean income" in income_table
    assert r"All workers\\Total income" in income_table
    assert r"Workers\\reassigned\\(millions)" in income_table
    with (ROOT / "replication/output/sample_audit.csv").open(newline="") as stream:
        sample = {r["item"]: float(r["value"]) for r in csv.DictReader(stream)}
    with (ROOT / "replication/output/baseline_groups_2025.csv").open(newline="") as stream:
        groups = list(csv.DictReader(stream))
    total_workers = sum(float(r["sum_w"]) for r in groups)
    assert math.isclose(total_workers, sample["target_weight_sum"], rel_tol=1e-12)
    assert f"Workers represented in 2025: {total_workers / 1e6:.1f} million." in income_table
    reassigned = {
        "formalize_same_size": lambda r: r["formal"] == "0",
        "formal_to_101": lambda r: r["formal"] == "1" and r["tamano_empresa"] != "101+",
        "informal_to_101": lambda r: r["formal"] == "0" and r["tamano_empresa"] != "101+",
        "combined_formal_101": lambda r: not (r["formal"] == "1" and r["tamano_empresa"] == "101+"),
    }
    with (ROOT / "replication/output/scenario_results.csv").open(newline="") as stream:
        scenarios = {(r["scenario"], r["population"]): r for r in csv.DictReader(stream)
                     if r["support"] == "unrestricted" and r["metric"] == "weekly"
                     and r["method"] == "predicted_common_smear"}
    for scenario, label in (
        ("formalize_same_size", "Informal to formal, same size"),
        ("formal_to_101", "Formal to formal 101+"),
        ("informal_to_101", "Informal to informal 101+"),
        ("combined_formal_101", "All workers to formal 101+"),
    ):
        gains = [float(scenarios[(scenario, p)]["gain_pct"]) for p in ("movers", "all")]
        moved_share = float(scenarios[(scenario, "all")]["moved_worker_share_pct"])
        expanded_movers = sum(float(r["sum_w"]) for r in groups if reassigned[scenario](r))
        assert math.isclose(moved_share, 100 * expanded_movers / total_workers, rel_tol=1e-12)
        expected = f"{label} & {expanded_movers / 1e6:.2f} & {gains[0]:.1f} & {gains[1]:.1f}" + r" \\"
        assert expected in income_table, scenario
    assert r"\rho_{o(i)}" not in all_slides
    assert r"\sum_{\tau\in\mathcal T}\mathbf{1}\{t=\tau\}" in details

    preferred = read(ROOT / "Paper/sections/regression_local_geography_formality_robustness_table.tex")
    informal, formal = table_body(preferred).split(r"\textit{Formal workers}")
    def panel_rows(part):
        result = {}
        for match in re.finditer(r"Firm size: ([0-9+-]+)\s*&([^\n]+)", part):
            result[match[1]] = numeric(match[2].split("&")[-1])
        return result
    informal, formal = panel_rows(informal), panel_rows(formal)
    displayed = selected_rows(frame(details, "Preferred Regression Output"))
    for size in informal:
        assert displayed[size] == [informal[size], formal[size]], (size, displayed[size])

    salary_source = selected_rows(read(ROOT / "Paper/sections/regression_salaried_robustness_table.tex"))
    salary_display = selected_rows(frame(backup, "Salaried-Worker Regression Output"))
    for size, cells in salary_display.items():
        assert cells == salary_source[size][-2:], (size, cells, salary_source[size])

    characteristics = selected_rows(read(ROOT / "Paper/sections/descriptive_worker_characteristics_2025_table.tex"))
    for size, cells in selected_rows(frame(main, "Why the Raw Relationship Is Not Enough")).items():
        assert cells == characteristics[size], (size, cells)

    for alias, source in (
        ("sequential_controls", "regression_firm_size_table"),
        ("common_geography", "regression_local_geography_robustness_table"),
    ):
        assert selected_rows(read(ROOT / f"Slides/generated/{alias}.tex")) == selected_rows(
            read(ROOT / f"Paper/sections/{source}.tex")), alias
    titles = ["Adding Controls Reduces the 101+/Solo Premium", "The Preferred Specification"]
    positions = [results.index(r"\begin{frame}{" + title + "}") for title in titles]
    assert positions == sorted(positions)
    assert details.index("Start with the Simplest Specification") < details.index(
        "Then Add Geography and Occupational Position") < details.index("Preferred Regression Output")
    paper = expand(ROOT / "main.tex")
    presentation = expand(ROOT / "presentacion_javeriana.tex")
    assert "bootstrap" not in paper.lower(), "Bootstrap results must stay omitted from the paper."
    assert "bootstrap" not in presentation.lower(), "Bootstrap results must stay omitted from the slides."
    for kind, key in (("table", "tables"), ("figure", "figures")):
        blocks = re.findall(r"\\begin\{" + kind + r"\}.*?\\end\{" + kind + r"\}", paper, re.S)
        expected = [re.search(r"\\label\{([^}]+)\}", block)[1] for block in blocks]
        assert [entry["label"] for entry in manifest[key]] == expected, key
    sequence = ["tab:firm-size-wage-premium-regressions", "tab:firm-size-local-geography-robustness",
                "tab:firm-size-local-geography-formality-robustness"]
    table_positions = [paper.index(r"\label{" + label + "}") for label in sequence]
    assert table_positions == sorted(table_positions)
    assert table_positions[-1] < paper.index(r"\appendix")
    for label in sequence + ["eq:common-premium", "eq:main"]:
        assert paper.count(r"\label{" + label + "}") == 1, label

    log_path = ROOT / "build/presentacion_javeriana.log"
    if log_path.exists():
        log = read(log_path)
        defects = re.findall(r".*(?:Overfull|undefined references|Undefined control sequence|Missing character).*", log)
        assert not defects, "\n".join(defects)
    print(f"PASS: {len(manifest['figures'])} figures and {len(manifest['tables'])} paper tables covered.")
    print(f"PASS: {main_slide_count} main slides, sequential controls before the preferred model, and elasticity benchmarks in the appendix.")
    print("PASS: source hashes, numeric coverage, preferred/salaried regression rows, and worker characteristics.")
    print("PASS: bootstrap summaries, reassigned-worker denominators, and dynamic notation.")


def render():
    import pypdfium2 as pdfium
    from PIL import Image, ImageDraw
    from pypdf import PdfReader

    pdf_path = ROOT / "build/presentacion_javeriana.pdf"
    output = ROOT / "build/slides_qa"
    output.mkdir(exist_ok=True)
    pdf = pdfium.PdfDocument(str(pdf_path))
    reader = PdfReader(pdf_path)
    text_pages = [page.extract_text() or "" for page in reader.pages]
    index = []
    for i, text in enumerate(text_pages, 1):
        index.append({"page": i, "title": text.splitlines()[0] if text else ""})
    (output / "page_index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    for offset in range(0, len(pdf), 20):
        sheet = Image.new("RGB", (1600, 1250), "#d6d6d6")
        draw = ImageDraw.Draw(sheet)
        for j in range(offset, min(offset + 20, len(pdf))):
            page = pdf[j]
            bitmap = page.render(scale=1.8)
            img = bitmap.to_pil().convert("RGB")
            img.save(output / f"slide_{j + 1:03d}.png")
            img.thumbnail((390, 220))
            x, y = ((j - offset) % 4) * 400 + 5, ((j - offset) // 4) * 250 + 22
            sheet.paste(img, (x, y))
            draw.text((x, y - 18), f"Page {j + 1}", fill="black")
            bitmap.close()
            page.close()
        sheet.save(output / f"contact_{offset // 20 + 1:02d}.png")
    print(f"Rendered {len(pdf)} PDF pages to {output}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    validate()
    if args.render:
        render()
