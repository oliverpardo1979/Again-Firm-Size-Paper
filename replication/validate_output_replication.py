"""Compare newly generated numeric outputs with a retained reference checkout."""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

DIRECTORIES = [
    'replication/regression_output', 'replication/preferred_output',
    'replication/salaried_output', 'replication/salaried_extensions_output',
    'replication/quadratic_output', 'replication/output',
    'replication/inference_audit_output', 'Paper/tables',
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--replica', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--since-epoch', type=float, required=True,
                        help='UTC Unix start time of the clean run, excluding copied reference tables.')
    args = parser.parse_args()
    results = []
    failures = []
    skipped = []
    for directory in DIRECTORIES:
        for path in sorted((args.replica / directory).glob('*.csv')):
            rel = path.relative_to(args.replica)
            if path.stat().st_mtime < args.since_epoch:
                skipped.append(rel.as_posix())
                continue
            reference = args.reference / rel
            if not reference.exists():
                failures.append(f'Missing reference: {rel}')
                continue
            try:
                x, y = pd.read_csv(path), pd.read_csv(reference)
                pd.testing.assert_frame_equal(x, y, check_dtype=False,
                                              check_exact=False, rtol=1e-9, atol=1e-7)
                numeric = x.select_dtypes(include=np.number).columns.intersection(y.select_dtypes(include=np.number).columns)
                delta = np.abs(x[numeric].to_numpy() - y[numeric].to_numpy())
                finite = delta[np.isfinite(delta)]
                results.append({'file': rel.as_posix(), 'rows': len(x), 'columns': len(x.columns),
                                'maximum_absolute_numeric_error': float(finite.max()) if len(finite) else 0.0})
            except (AssertionError, ValueError) as exc:
                failures.append(f'{rel}: {str(exc)[:1800]}')
    assert results, 'No numeric outputs found'
    args.output.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(results).to_csv(args.output / 'numeric_replication_checks.csv', index=False)
    summary = {'matched_csv_files': len(results), 'failures': failures,
               'atol': 1e-7, 'rtol': 1e-9,
               'copied_or_older_files_not_tested': skipped,
               'scope': 'CSV files generated after the clean run began. No model-cache or PDF byte comparison.'}
    (args.output / 'numeric_replication_validation.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    assert not failures, 'Numeric replication differences require review'


if __name__ == '__main__':
    main()
