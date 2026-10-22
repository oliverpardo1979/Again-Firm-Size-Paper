"""Convert validated annual primary-job records to the manuscript input schema.

The input directory contains complete_YEAR_private.csv, produced by the public
GEIH reconstruction. The Stata file is local only and is excluded from Git.
"""
from pathlib import Path
import argparse
import json
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
YEARS = list(range(2008, 2020)) + list(range(2021, 2026))
SIZES = ['Solo', '2-3', '4-5', '6-10', '11-19', '20-30', '31-50', '51-100', '101+']
SECTORS = ['Agricultura, ganader\u00eda, silvicultura y pesca', 'Minas y canteras',
    'Industrias manufactureras', 'Electricidad, gas, agua y saneamiento',
    'Construcci\u00f3n', 'Comercio y reparaci\u00f3n', 'Alojamiento y servicios de comida',
    'Transporte y almacenamiento', 'Informaci\u00f3n y comunicaciones',
    'Actividades financieras y de seguros', 'Inmobiliarias, profesionales y administrativas',
    'Administraci\u00f3n p\u00fablica y defensa', 'Educaci\u00f3n', 'Salud y asistencia social',
    'Artes, recreaci\u00f3n y otros servicios', 'Hogares como empleadores',
    'Organizaciones extraterritoriales']
EDUCATION = {1: 'Ninguno', 2: 'Preescolar', 3: 'B\u00e1sica primaria',
    4: 'B\u00e1sica secundaria', 5: 'Media', 6: 'Superior o universitaria', 9: 'No sabe, no informa'}
OCCUPATIONS = ['Obrero o empleado de empresa particular', 'Obrero o empleado del gobierno',
    'Empleado dom\u00e9stico', 'Trabajador por cuenta propia', 'Patr\u00f3n o empleador',
    'Trabajador familiar sin remuneraci\u00f3n', 'Trabajador sin remuneraci\u00f3n en otros hogares',
    'Jornalero o pe\u00f3n', 'Otro']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/GEIH_primary_income_2008_2025.dta')
    args = parser.parse_args()
    frames, audit = [], []
    for year in YEARS:
        x = pd.read_csv(args.source / f'complete_{year}_private.csv')
        assert x.year.eq(year).all() and set(x.MES) == set(range(1, 13))
        assert x.age.between(15, 120).all() and x.weight.gt(0).all()
        assert x.primary_monthly.gt(0).all() and x.hours.between(0, 168, inclusive='right').all()
        assert not x.duplicated(['MES', 'DIRECTORIO', 'SECUENCIA_P', 'ORDEN']).any()
        hourly = 12 * x.primary_monthly / (52 * x.hours)
        assert np.max(np.abs(np.log(hourly * x.price_factor) - x.log_primary)) < 1e-10
        d = pd.DataFrame({
            'anio': x.year.astype('int32'), 'edad': x.age, 'edad2': x.age**2,
            'depto': x.department.astype('int32'), 'sector_hom_cod': x.sector.astype('int32'),
            'sector': x.sector.map(dict(enumerate(SECTORS, 1))),
            'tamano_hom_cod': x['size'].astype('int32'),
            'tamano_empresa': x['size'].map(dict(enumerate(SIZES, 1))),
            'educ_hom_cod': x.education.astype('int32'), 'educacion': x.education.map(EDUCATION),
            'posicion_ocupacional': x.occupation.astype('int32'),
            'posicion_ocupacional_label': x.occupation.map(dict(enumerate(OCCUPATIONS, 1))),
            'mujer': x.female.astype('int32'), 'sexo': x.female.map({0: 'Hombre', 1: 'Mujer'}),
            'formal': x.formal.astype('int32'), 'formalidad': x.formal.map({0: 'Informal', 1: 'Formal'}),
            'fex': x.weight, 'horas': x.hours, 'ingreso_laboral_hora': hourly,
            'ingreso_hora_real': np.exp(x.log_primary), 'log_ingreso_hora_real': x.log_primary,
            'factor_precios_2025': x.price_factor, 'pensionado_ocupado': 0,
            'primary_monthly': x.primary_monthly,
        })
        for key in ['MES', 'DIRECTORIO', 'SECUENCIA_P', 'ORDEN']:
            d[key] = x[key]
        assert not d.isna().any().any()
        audit.append({'year': year, 'n': len(d), 'workers': d.fex.sum(),
                      'salaried_n': int(x.salaried.sum()), 'months': 12})
        frames.append(d)
        print(f'{year}: {len(d):,}', flush=True)
    d = pd.concat(frames, ignore_index=True)
    assert len(d) == 5426316
    args.output.parent.mkdir(parents=True, exist_ok=True)
    d.to_stata(args.output, write_index=False, version=118,
               data_label='GEIH primary income 2026-10-21, aligned occupation codes')
    out = ROOT / 'replication/primary_income_output'
    out.mkdir(exist_ok=True)
    pd.DataFrame(audit).to_csv(out / 'input_coverage.csv', index=False)
    (out / 'input_definition.json').write_text(json.dumps({
        'version': 'primary-income-2026-10-21', 'observations': len(d),
        'income_components': ['P6500', 'P6590S1', 'P6600S1', 'P6750'],
        'excluded_second_job_component': 'P7070', 'missing_codes': [98, 99],
        'age_bounds_inclusive': [15, 120], 'positive_primary_income': True,
        'weekly_hours': 'main job, positive and at most 168',
        'weight_divisor': 12, 'weight_2008_2009': 'CNPV 2018 retrospective factors',
        'weight_2010_2019': 'official empalme FEX_C, not bare CNPV 2018 factors',
        'weight_2021_2025': 'marco 2018 FEX_C18',
        'occupation_codes': 'aligned across questionnaires, not raw post-2020 codes',
        'price_conversion': 'same annual end-of-year CPI factors as the previous paper',
    }, indent=2) + '\n')
    print(args.output, flush=True)


if __name__ == '__main__':
    main()
