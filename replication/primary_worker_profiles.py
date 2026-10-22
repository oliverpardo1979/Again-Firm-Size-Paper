"""Check detailed 2025 activities against the corrected, keyed sample."""
from pathlib import Path
import argparse
import numpy as np
import pandas as pd
import geih_public_reader as src

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('records', type=Path)
args = parser.parse_args()
out = ROOT / 'replication/formal_solo_output'
out.mkdir(exist_ok=True)
cache = ROOT / 'data/activity_audit'
cache.mkdir(exist_ok=True)
src.WANTED = set(src.KEY + ['RAMA4D_R4', 'RAMA4D'])
raw = src.load_year(2025, manifest_dir=cache)
activity, field = src.choose(raw, ['RAMA4D_R4', 'RAMA4D'])
raw['activity'] = activity
d = pd.read_csv(args.records / 'complete_2025_private.csv')
d = d.merge(raw[src.KEY + ['activity']], on=src.KEY, how='left', validate='one_to_one', indicator=True)
assert d._merge.eq('both').all()
solo = d.loc[d.formal.eq(1) & d['size'].eq(1)].copy()
rows = []
for higher, group in solo.groupby(solo.education.eq(6)):
    rows.append(dict(higher_education=higher, observations=len(group),
        own_account_pct=100*np.average(group.occupation.eq(4), weights=group.weight),
        mean_hourly_income_2025_cop=np.average(np.exp(group.log_primary), weights=group.weight),
        share_of_formal_solo_pct=100*group.weight.sum()/solo.weight.sum()))
pd.DataFrame(rows).to_csv(out / 'education_profiles_2025.csv', index=False)
high = solo.loc[solo.education.eq(6)]
activities = high.groupby('activity').agg(observations=('weight', 'size'), workers=('weight', 'sum'))
activities['share_of_higher_education_formal_solo_pct'] = 100*activities.workers/high.weight.sum()
selected = activities.loc[[6910, 6920]].reset_index().rename(columns={'activity': 'code'})
assert selected.observations.ge(20).all()
selected['activity'] = ['Legal services', 'Accounting, auditing and tax consultancy']
selected.drop(columns='workers').to_csv(out / 'selected_activities_2025.csv', index=False)
pd.DataFrame([
    dict(check='All current records matched public person keys', passed=True),
    dict(check='Legal and accounting services are the top two activities',
         passed=activities.workers.rank(ascending=False).loc[[6910, 6920]].tolist() == [1, 2]),
]).to_csv(out / 'checks.csv', index=False)
print(pd.DataFrame(rows).to_string(index=False))
print(selected.drop(columns='workers').to_string(index=False))
print('Ranks among activities:', activities.workers.rank(ascending=False).loc[[6910, 6920]].tolist())
