"""Validate the separate inference audit and record available design metadata."""
from pathlib import Path
import json
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/inference_audit_output"
OLD = ROOT / "replication/preferred_output"
conventional = pd.read_csv(OUT / "conventional.csv")
assert len(conventional) == 180
assert not conventional.duplicated(["model", "contrast", "clustering"]).any()
assert conventional.p.between(0, 1).all() and conventional.se.gt(0).all()
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
summary["log_contrast_or_elasticity"] = conventional.drop_duplicates(["model", "contrast"]).set_index(["model", "contrast"]).estimate
summary["premium_percent"] = [100*np.expm1(b) if model == "preferred" and not contrast.startswith("Formal-minus") else np.nan
    for (model, contrast), b in summary.log_contrast_or_elasticity.items()]
summary.to_csv(OUT / "comparison_all_contrasts.csv")

# Read names and labels only, never publish raw records or household identifiers.
source = ROOT / "data/GEIH_primary_income_2008_2025.dta"
with pd.io.stata.StataReader(source) as reader:
    labels = reader.variable_labels()
metadata = {"source": source.name, "variables_and_labels": labels,
            "note": "Original person and household merge keys are retained. Explicit survey PSU, segment and sampling-stratum identifiers are not retained. Historical bootstrap outputs were not re-estimated for this input."}
(OUT / "model_data_metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=True), encoding="utf-8")

print("Validated", len(checks), "existing numerical results. Maximum difference", max(x["error"] for x in checks))
print("Historical bootstrap files were not used in this validation.")
