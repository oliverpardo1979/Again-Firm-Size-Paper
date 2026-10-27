"""Reconstruct the adopted complete-calendar sample from public DANE records."""
from pathlib import Path
import argparse
import os
import sys
import json
import zipfile
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'data/primary_records'
RAW = Path(os.environ["GEIH_RAW_DIR"]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
import geih_public_reader as src
KEY, MAIN = src.KEY, src.MAIN
YEARS = list(range(2008, 2020)) + list(range(2021, 2026))


def build(year):
    raw = src.load_year(year, manifest_dir=OUT)
    assert not raw.duplicated(KEY).any()
    assert set(raw.MES.unique()) == set(range(1, 13))
    d = raw.copy()
    if year in (2008, 2009):
        path = RAW / f'Fex proyecciones CNPV 2018_{year}.zip'
        with zipfile.ZipFile(path) as z:
            member = next(n for n in z.namelist() if n.lower().endswith('.csv'))
            w = pd.read_csv(z.open(member), sep=';', encoding='utf-8-sig', dtype=str)
        w.columns = [src.normalize(c) for c in w]
        for c in KEY + ['FEX_C18']:
            w[c] = pd.to_numeric(w[c].str.replace(',', '.', regex=False), errors='raise')
        assert not w.duplicated(KEY).any()
        d = d.drop(columns='FEX_C18', errors='ignore').merge(
            w[KEY + ['FEX_C18']], on=KEY, how='left', validate='one_to_one', indicator=True)
        assert d._merge.eq('both').all()
        d = d.drop(columns='_merge')
        wname = 'FEX_C18'
        provenance = 'CNPV2018 retrospective population calibration'
    elif year <= 2019:
        wname = 'FEX_C'
        provenance = 'Official GEIH empalme, CNPV2018 population calibration and frame bridge'
    else:
        wname = 'FEX_C18'
        provenance = 'GEIH marco2018, CNPV2018 population calibration'
    assert wname in d, (year, wname, list(d))
    d['weight'] = d[wname] / 12
    d['year'] = year
    d['hours'] = d.P6800.where(d.P6800.gt(0) & d.P6800.le(168))
    price = [json.loads((ROOT / 'replication/primary_income_output/price_factors.json').read_text())[str(year)]]
    d['price_factor'] = price[0]
    age, aname = src.choose(d, ['EDAD', 'P6040'] if 2015 <= year <= 2019 or year == 2022 else ['P6040', 'EDAD'])
    d['age'] = age.where(age.between(15, 120))
    sex, xname = src.choose(d, ['P6020', 'P3271'])
    d['female'] = sex.map({1: 0, 2: 1})
    d['formal'] = d.P6920.map({1: 1, 2: 0})
    size, sname = src.choose(d, ['P3069', 'P6870'] if year >= 2021 else ['P6870', 'P3069'])
    d['size'] = size.where(size.between(1, 10 if sname == 'P3069' else 9)).replace({10: 9})
    education, ename = src.choose(d, ['P6210', 'P3042', 'NIVEL_MAS_ALTO'])
    mapping = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 9, 9: 9, 99: 9} if year < 2021 else {
        1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 5, **{v: 6 for v in range(7, 14)}, 99: 9}
    d['education'] = education.map(mapping)
    industry, rname = src.choose(d, ['RAMA2D_R4', 'RAMA2D'])
    d['sector'] = src.sector(industry, rname == 'RAMA2D_R4')
    d['department'] = d.DPTO.where(d.DPTO.gt(0))
    d['occupation'] = d.P6430.where(d.P6430.between(1, 9))
    if year >= 2021:
        d['occupation'] = d.occupation.replace({7: 8, 8: 9})
    d['salaried'] = d.occupation.isin([1, 2, 3, 8]).astype(int)
    for c in MAIN + ['P7070']:
        if c not in d:
            d[c] = np.nan
        d[c + '_observed'] = d[c].mask(d[c].isin([98, 99]))
    d['primary_monthly'] = d[[c + '_observed' for c in MAIN]].sum(axis=1, min_count=1)
    eligible = d.OCI.eq(1) & age.between(15, 120)
    income_status = pd.Series('positive', index=d.index)
    income_status.loc[d.primary_monthly.le(0)] = 'zero_or_negative'
    income_status.loc[d.primary_monthly.isna()] = 'all_components_missing'
    selection = d.loc[eligible, ['salaried', 'formal', 'size']].copy()
    selection['income_status'] = income_status.loc[eligible]
    selection['sentinel_component'] = d.loc[eligible, MAIN].isin([98, 99]).any(axis=1).astype(int)
    selection['year'] = year
    selection.groupby(['year', 'salaried', 'formal', 'size', 'income_status'], dropna=False).agg(
        observations=('income_status', 'size'),
        any_sentinel=('sentinel_component', 'sum'),
    ).reset_index().to_csv(OUT / f'income_selection_{year}.csv', index=False)
    d['log_primary'] = np.log((12 * d.primary_monthly / (52 * d.hours) * price[0]).where(d.primary_monthly.gt(0)))
    controls = ['age', 'female', 'formal', 'size', 'education', 'sector', 'department', 'occupation']
    masks = {
        'occupied': d.OCI.eq(1),
        'age_15_120': age.between(15, 120),
        'positive_primary_income': d.primary_monthly.gt(0),
        'valid_primary_hours': d.hours.notna(),
        'positive_weight': d.weight.gt(0),
        'complete_controls': d[controls].notna().all(axis=1),
    }
    keep = pd.Series(True, index=d.index)
    attrition = []
    for name, mask in masks.items():
        before = keep.sum()
        keep &= mask
        attrition.append(dict(year=year, step=name, removed=int(before-keep.sum()), remaining=int(keep.sum())))
    pd.DataFrame(attrition).to_csv(OUT / f'attrition_{year}.csv', index=False)
    coverage = []
    for month in range(1, 13):
        raw_month = d.MES.eq(month)
        selected = raw_month & keep
        row = dict(year=year, month=month, raw_occupied=int(raw_month.sum()), n=int(selected.sum()),
                   annualized_workers=float(d.loc[selected, 'weight'].sum()),
                   salaried_n=int(d.loc[selected, 'salaried'].sum()),
                   primary_observed=int(d.loc[raw_month, 'primary_monthly'].notna().sum()),
                   total_income_observed=int(d.loc[raw_month, 'INGLABO'].notna().sum()))
        for c in MAIN:
            row[c + '_observed_n'] = int(d.loc[raw_month, c + '_observed'].notna().sum())
        coverage.append(row)
    pd.DataFrame(coverage).to_csv(OUT / f'coverage_{year}.csv', index=False)
    x = d.loc[keep].copy()
    assert set(x.MES.unique()) == set(range(1, 13))
    assert x.age.between(15, 120).all() and x.weight.gt(0).all()
    assert np.isfinite(x.log_primary).all()
    cols = [c for c in src.MODELCOLS if c != 'log_income'] + KEY + ['primary_monthly', 'log_primary']
    x[cols].to_csv(OUT / f'complete_{year}_private.csv', index=False)
    x.loc[x.occupation.isin([6, 7]), cols].to_csv(OUT / f'unpaid_positive_{year}_private.csv', index=False)
    result = dict(year=year, n=len(x), salaried_n=int(x.salaried.sum()), workers=float(x.weight.sum()),
                  months=sorted(int(m) for m in x.MES.unique()), minimum_age=float(x.age.min()),
                  weight_variable=wname, weight_method=provenance, weight_divisor=12,
                  unpaid_positive_n=int(x.occupation.isin([6, 7]).sum()),
                  variables=dict(age=aname, sex=xname, size=sname, education=ename, industry=rname))
    (OUT / f'validation_{year}.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--years', type=int, nargs='+', default=YEARS)
    args = parser.parse_args()
    for year in args.years:
        build(year)
