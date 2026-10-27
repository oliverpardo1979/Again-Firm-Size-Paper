"""Validate a fresh all-year reconstruction without importing an earlier audit.

Run only after rebuilding the annual records and converting them to Stata.
Outputs contain aggregate diagnostics and file hashes, never worker records.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
YEARS = list(range(2008, 2020)) + list(range(2021, 2026))


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--records', type=Path, required=True)
    parser.add_argument('--rebuilt', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    coverage, attrition, annual = [], [], []
    for year in YEARS:
        c = pd.read_csv(args.records / f'coverage_{year}.csv')
        a = pd.read_csv(args.records / f'attrition_{year}.csv')
        v = json.loads((args.records / f'validation_{year}.json').read_text())
        assert len(c) == 12 and set(c.month) == set(range(1, 13)), year
        assert c.year.eq(year).all() and c.n.sum() == v['n'], year
        assert c.salaried_n.sum() == v['salaried_n'], year
        assert np.isclose(c.annualized_workers.sum(), v['workers'], rtol=1e-12), year
        assert a.remaining.iloc[-1] == v['n'], year
        assert v['minimum_age'] >= 15 and v['weight_divisor'] == 12, year
        coverage.append(c)
        attrition.append(a)
        annual.append({k: v[k] for k in ('year', 'n', 'salaried_n', 'workers',
                                        'minimum_age', 'weight_variable', 'weight_method')})
    coverage = pd.concat(coverage, ignore_index=True)
    assert len(coverage) == 204 and coverage.n.sum() == 5426316
    coverage.to_csv(args.output / 'monthly_coverage.csv', index=False)
    pd.concat(attrition, ignore_index=True).to_csv(args.output / 'sample_attrition.csv', index=False)
    pd.DataFrame(annual).to_csv(args.output / 'annual_reconstruction.csv', index=False)

    # Compare every record and every column, not only 2025 or aggregate counts.
    current = pd.read_stata(args.baseline, convert_categoricals=False, chunksize=200000)
    rebuilt = pd.read_stata(args.rebuilt, convert_categoricals=False, chunksize=200000)
    rows = 0
    chunks = 0
    for x, y in zip(current, rebuilt, strict=True):
        pd.testing.assert_frame_equal(x, y, check_exact=False, rtol=1e-12, atol=1e-10)
        rows += len(x)
        chunks += 1
    assert rows == int(coverage.n.sum())
    files = []
    manifest_path = ROOT / 'replication/primary_income_output/raw_source_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    expected_hashes = {r['filename']: r.get('sha256') for r in manifest}
    for path in sorted(args.source_dir.glob('*.zip')):
        sha = digest(path)
        expected = expected_hashes.get(path.name)
        if expected:
            assert sha == expected, path.name
        files.append({'filename': path.name, 'bytes': path.stat().st_size,
                      'sha256': sha, 'matched_download_manifest': bool(expected)})
    assert files, 'No original archives found'
    assert set(expected_hashes).issubset({x['filename'] for x in files}), 'Missing required source archives'
    pd.DataFrame(files).to_csv(args.output / 'source_archive_hashes.csv', index=False)
    summary = {'records_compared': rows, 'chunks_compared': chunks,
               'months_rebuilt': len(coverage), 'years_rebuilt': YEARS,
               'baseline_sha256': digest(args.baseline), 'rebuilt_sha256': digest(args.rebuilt),
               'all_columns_equal_rtol': 1e-12, 'all_columns_equal_atol': 1e-10,
               'source_archives': len(files),
               'note': 'Stata file byte hashes can differ because of creation timestamps.'}
    (args.output / 'reconstruction_validation.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
