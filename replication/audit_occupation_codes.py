"""Check questionnaire routing in the original 2021 files, exporting aggregates only."""
import argparse
import io
import warnings
import zipfile
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("archives", nargs="+", type=Path)
args = parser.parse_args()
rows = []
for path in args.archives:
    with zipfile.ZipFile(path) as z:
        files = [n for n in z.namelist() if n.lower().endswith("/ocupados.dta")]
        assert files, path
        for name in files:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UnicodeWarning)
                d = pd.read_stata(io.BytesIO(z.read(name)), convert_categoricals=False)
            d.columns = d.columns.str.upper()
            for code, group in d.groupby("P6430"):
                rows.append(dict(archive=path.name, member=name, code=int(code), n=len(group),
                    salary_question_nonmissing=int(group.P6500.notna().sum()),
                    independent_question_nonmissing=int(group.P6765.notna().sum())))
            print(name, flush=True)
result = pd.DataFrame(rows)
seven = result[result.code == 7]
eight = result[result.code == 8]
assert len(seven) == len(eight) == 12
assert (seven.salary_question_nonmissing > 0).all()
assert (seven.independent_question_nonmissing == 0).all()
assert (eight.salary_question_nonmissing == 0).all()
assert (eight.independent_question_nonmissing == eight.n).all()
out = ROOT / "replication/salaried_output"
out.mkdir(exist_ok=True)
result.to_csv(out / "raw_2021_routing_audit.csv", index=False)
print("Verified code 7 follows salary questions and code 8 follows independent/other questions in all 12 months.")
