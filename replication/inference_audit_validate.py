"""Validate the separate inference audit and record available design metadata."""
from pathlib import Path
import csv
import json
import zipfile
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/inference_audit_output"
OLD = ROOT / "replication/preferred_output"
conventional = pd.read_csv(OUT / "conventional.csv")
wild = pd.read_csv(OUT / "wild_bootstrap.csv")
assert len(conventional) == 180 and len(wild) == 135
assert not wild.duplicated(["model", "contrast", "clustering"]).any()
assert (wild.B_returned == 9999).all()
assert (wild.finite_boot_t + wild.discarded_boot_t == 9999).all()
assert (wild.nonfinite_boot_t == 0).all()
invalid = wild[wild.discarded_boot_t.gt(0)]
assert len(invalid) == 1
assert invalid.iloc[0].contrast == "Formal change 101+/solo 2008-2025"
assert invalid.iloc[0].clustering == "Two-way sector + department"
assert invalid.iloc[0].discarded_boot_t == 209
assert pd.read_csv(OUT / "bootstrap_validation.csv").t_error.abs().max() < 1e-7
checks = []

def compare(label, clustering, old):
    row = conventional[(conventional.contrast == label) &
                       (conventional.clustering == clustering)].iloc[0]
    for current, prior in [("estimate", "estimate"), ("se", "std.error"), ("p", "p.value")]:
        error = abs(row[current] - old[prior])
        assert error < 1e-7, (label, clustering, current, error)
        checks.append(dict(contrast=label, clustering=clustering, field=current, error=error))

for _, row in pd.read_csv(OLD / "extension_clustering_sensitivity.csv").iterrows():
    label = (row["group"] + " change 101+/solo 2008-2025"
             if row.exercise.startswith("Endpoint") else row["group"] + " elasticity")
    compare(label, row.clustering, row)
for _, row in pd.read_csv(OLD / "profiles.csv").iterrows():
    if row.reference == "Solo":
        compare(row["group"] + " " + row["size"] + "/solo", "Sector-department", row)
for _, row in pd.read_csv(OLD / "formal_informal_gaps.csv").iterrows():
    compare("Formal-informal at " + row["size"], "Sector-department", row)
pd.DataFrame(checks).to_csv(OUT / "existing_results_validation.csv", index=False)

summary = conventional.pivot(index=["model", "contrast"], columns="clustering", values="p")
summary.columns = ["p_conventional_" + x for x in summary.columns]
boot = wild.pivot(index=["model", "contrast"], columns="clustering", values="p_wild")
boot.columns = ["p_WCR11_" + x for x in boot.columns]
summary = summary.join(boot)
summary["discarded_WCR11_draws_two_way"] = wild[wild.clustering.eq("Two-way sector + department")].set_index(["model", "contrast"]).discarded_boot_t
summary["log_contrast_or_elasticity"] = conventional.drop_duplicates(["model", "contrast"]).set_index(["model", "contrast"]).estimate
summary["premium_percent"] = [100*np.expm1(b) if model == "preferred" and not contrast.startswith("Formal-minus") else np.nan
    for (model, contrast), b in summary.log_contrast_or_elasticity.items()]
summary.to_csv(OUT / "comparison_all_contrasts.csv")

# Read names and labels only, never publish raw records or household identifiers.
source = ROOT.parent / "CJC-Monitor/Datos/Processed/Paper-GEIH_base_modelo_personas_2008_2025.dta"
with pd.io.stata.StataReader(source) as reader:
    labels = reader.variable_labels()
metadata = {"source": source.name, "variables_and_labels": labels,
            "note": "No explicit survey PSU, segment, sampling-stratum, or household keys are retained in this model file."}
(OUT / "model_data_metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=True), encoding="utf-8")

raw = ROOT.parent / "Informe_Educacion/outputs/microdata_raw"
headers = []
for archive in sorted(raw.glob("GEIH_*.zip")):
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            if not name.lower().endswith(".csv"):
                continue
            with z.open(name) as f:
                line = f.readline().decode("utf-8-sig", errors="replace").strip()
            dialect = csv.Sniffer().sniff(line, delimiters=";,\t")
            columns = next(csv.reader([line], dialect=dialect))
            headers.append({"archive": archive.name, "file": name, "columns": columns,
                            "explicit_design_names": [x for x in columns if x.upper() in
                                {"UPM", "PSU", "USM", "SEGMENTO", "SEGMENT", "ESTRATO", "ESTRATO_MUESTRAL", "STRATA"}]})
(OUT / "public_raw_headers.json").write_text(json.dumps(headers, indent=2, ensure_ascii=True), encoding="utf-8")
assert all(len(x["columns"]) > 1 for x in headers)
print("Validated", len(checks), "existing numerical results. Maximum difference", max(x["error"] for x in checks))
print("Inspected", len(headers), "CSV headers in", len({x["archive"] for x in headers}), "public archives")
print("Explicit design-name matches", [(x["archive"], x["file"], x["explicit_design_names"]) for x in headers if x["explicit_design_names"]])
print("Warnings:", wild.warnings.dropna().unique().tolist())
