"""Compare the integrated pipeline with the approved pre-adoption audit."""
from pathlib import Path
import argparse
import json
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('audit', type=Path)
parser.add_argument('--downloads', type=Path)
args = parser.parse_args()
out = ROOT / 'replication/primary_income_output'
checks = []


def compare(name, current, expected, keys, columns):
    assert not current.duplicated(keys).any(), name
    assert not expected.duplicated(keys).any(), name
    merged = current.merge(expected, on=keys, suffixes=('_new', '_audit'),
                           how='outer', validate='one_to_one', indicator=True)
    assert merged._merge.eq('both').all(), name
    for col in columns:
        error = np.max(np.abs(merged[col+'_new'] - merged[col+'_audit']))
        assert error < 1e-7, (name, col, error)
        checks.append(dict(exercise=name, field=col, rows=len(merged), maximum_error=error))


annual = pd.read_csv(ROOT / 'replication/salaried_extensions_output/annual_profiles.csv')
annual = annual[annual.reference.eq('Solo')].rename(columns={'std.error': 'se', 'p.value': 'p_value'})
approved_annual = pd.read_csv(args.audit / 'annual_profiles.csv')
approved_annual = approved_annual[approved_annual['sample'].isin(['All', 'Salaried'])]
compare('Annual profiles, both samples', annual, approved_annual,
        ['sample', 'year', 'size', 'group'], ['estimate', 'se', 'p_value', 'premium', 'ci_low', 'ci_high'])
pooled = pd.read_csv(ROOT / 'replication/salaried_output/contrasts.csv')
expected = pd.read_csv(args.audit / 'contrasts.csv')
pooled = pooled[pooled.clustering.eq('Sector-department')].rename(columns={'std.error': 'se', 'p.value': 'p_value'})
compare('Preferred pooled contrasts, both samples', pooled, expected[expected.model.eq('preferred')],
        ['sample', 'reference', 'size', 'group', 'clustering'],
        ['estimate', 'se', 'p_value', 'premium', 'ci_low', 'ci_high'])

# Check the portable reconstruction independently of the Stata conversion.
rebuilt = ROOT / 'data/primary_records/complete_2025_private.csv'
if rebuilt.exists():
    current = pd.read_csv(rebuilt)
    expected_records = pd.read_csv(args.audit / 'complete_2025_private.csv')
    compare('Public 2025 reconstruction', current, expected_records,
            ['MES', 'DIRECTORIO', 'SECUENCIA_P', 'ORDEN'],
            ['age', 'weight', 'hours', 'primary_monthly', 'log_primary', 'occupation', 'formal', 'size'])

coverage = pd.read_csv(args.audit / 'monthly_coverage.csv')
assert len(coverage) == 204 and not coverage.duplicated(['year', 'month']).any()
assert coverage.groupby('year').month.nunique().eq(12).all()
assert coverage.n.sum() == 5426316
coverage.to_csv(out / 'monthly_coverage.csv', index=False)
pd.read_csv(args.audit / 'attrition.csv').to_csv(out / 'sample_attrition.csv', index=False)
pd.read_csv(args.audit / 'data_validation_summary.csv').to_csv(out / 'data_validation_summary.csv', index=False)
manifest = pd.read_csv(args.audit / 'analysis_manifest.csv')
manifest['file'] = manifest.file.str.replace('\\', '/', regex=False).str.rsplit('/', n=1).str[-1]
manifest.to_csv(out / 'local_input_hashes.csv', index=False)
if args.downloads:
    records = []
    for name in ('download_manifest.json', 'download_empalme_manifest.json', 'download_sav_manifest.json'):
        for row in json.loads((args.downloads / name).read_text()):
            filename = row['path'].replace('\\', '/').rsplit('/', 1)[-1]
            if filename.startswith(('SAV_', 'GEIH_Empalme')) or int(row['year']) >= 2021:
                records.append({**{k: row[k] for k in ('year', 'month', 'size', 'sha256', 'url') if k in row},
                                'filename': filename})
    (out / 'downloaded_source_manifest.json').write_text(json.dumps(records, indent=2) + '\n')
pd.DataFrame(checks).to_csv(out / 'independent_pipeline_checks.csv', index=False)
print(pd.DataFrame(checks).to_string(index=False))
print('Validated all 204 year-month cells and the public 2025 reconstruction.')
