"""Rebuild model inputs and audit primary-income components year by year."""
from pathlib import Path
import os
import csv
import io
import json
import re
import zipfile
import numpy as np
import pandas as pd

OUT=Path(os.environ["GEIH_RAW_DIR"]).resolve()
KEY=['MES','DIRECTORIO','SECUENCIA_P','ORDEN']
MAIN=['P6500','P6590S1','P6600S1','P6750']
WANTED=set(KEY+['FEX_C_2011','FEX_C18','FEX_C','DPTO','OCI','INGLABO','RAMA2D_R4','RAMA2D',
    'P6430','P6920','P3069','P6870','P6800','P7040','P7070','P6020','P3271','P6040','EDAD',
    'RAMA4D_R4','RAMA4D','P6210','P3042','NIVEL_MAS_ALTO','P550','P6610S1','P6620S1','P6500','P6590S1','P6600S1','P6750'])
MODELCOLS=['year','department','age','sector','size','education','occupation','female','formal',
           'weight','hours','log_income','salaried','price_factor']
GROUPKEY=[c for c in MODELCOLS if c not in ['weight','salaried','price_factor','log_income']]+['rounded_income']


def normalize(s):
    return s.encode('ascii','ignore').decode().upper().strip()


def read_module(z,name):
    with z.open(name) as f:
        content=f.read()
    try:
        content.decode('utf-8-sig')
        encoding='utf-8-sig'
    except UnicodeDecodeError:
        encoding='cp1252'
    line=content.decode(encoding).splitlines()[0]
    sep=max([';',',','\t'],key=lambda s:line.count(s))
    names=next(csv.reader([line],delimiter=sep))
    keep={normalize(n):n for n in names if normalize(n) in WANTED}
    d=pd.read_csv(io.BytesIO(content),sep=sep,encoding=encoding,decimal=',' if sep!=',' else '.',
                  usecols=list(keep.values()),na_values=[' ','.'],low_memory=False)
    d.columns=[normalize(c) for c in d.columns]
    for c in d:
        if not pd.api.types.is_numeric_dtype(d[c]):
            values=d[c].astype('string').str.strip()
            thousands=values.str.fullmatch(r'-?\d{1,3}(,\d{3}){2,}(\.\d+)?').fillna(False)
            if thousands.any():
                values=values.str.replace(',','',regex=False)
            elif sep!=';':
                # A comma-separated CSV may still quote decimal commas.
                values=values.str.replace(',','.',regex=False)
            d[c]=values
        numeric=pd.to_numeric(d[c],errors='coerce').astype(float)
        invalid=d[c].notna()&numeric.isna()
        if invalid.any():
            # The original consolidation uses destring, force. Record every such conversion.
            print(json.dumps(dict(module=name,variable=c,non_numeric_to_missing=int(invalid.sum()))),flush=True)
        d[c]=numeric
    return d


def choose(d,names):
    for n in names:
        if n in d:
            return d[n],n
    return pd.Series(np.nan,index=d.index),'MISSING'


def sector(s,rev4):
    old={1:[1,2,5],2:range(10,15),3:range(15,38),4:[40,41,90],5:[45],6:range(50,53),
         7:[55],8:range(60,64),9:[64,72],10:range(65,68),11:[70,71,73,74],12:[75],
         13:[80],14:[85],15:range(91,94),16:range(95,98),17:[99]}
    new={1:range(1,4),2:range(5,10),3:range(10,34),4:range(35,40),5:range(41,44),6:range(45,48),
         7:[55,56],8:range(49,54),9:range(58,64),10:range(64,67),11:[68,*range(69,76),*range(77,83)],
         12:[84],13:[85],14:range(86,89),15:range(90,97),16:[97,98],17:[99]}
    result=pd.Series(np.nan,index=s.index)
    for code,vals in (new if rev4 else old).items():
        result.loc[s.isin(vals)]=code
    return result


def files_for(year):
    empalme = OUT / f'GEIH_Empalme_{year}.zip'
    if empalme.exists():
        return [empalme]
    if year == 2021:
        return sorted(OUT.glob('GEIH_2021_marco2018_*.zip'))
    return sorted(OUT.glob(f'GEIH_{year}_*.zip'))


def archive_stream(year):
    for path in files_for(year):
        with zipfile.ZipFile(path) as outer:
            nested=[n for n in outer.namelist() if n.lower().endswith('.zip')]
            if nested:
                for name in nested:
                    with zipfile.ZipFile(io.BytesIO(outer.read(name))) as inner:
                        if any(n.lower().endswith('.csv') for n in inner.namelist()):
                            yield Path(path.name)/name,inner
            else:
                yield path,outer


def load_year(year, manifest_dir=None):
    canonical=OUT/f'historical_raw_{year}_private.csv'
    if canonical.exists():
        return pd.read_csv(canonical)
    parts=[]
    records=[]
    for path,z in archive_stream(year):
        if True:
            members=[n for n in z.namelist() if n.lower().endswith('.csv')]
            occ=[n for n in members if re.search(r'(^|/| - )ocupados',n,re.I)]
            # Cabecera includes metropolitan areas. Do not count the Area files twice.
            geographic=any('cabecera' in n.lower() for n in occ)
            if geographic:
                occ=[n for n in occ if 'cabecera' in n.lower() or 'resto' in n.lower()]
            assert occ,(path,'no occupied modules')
            for name in occ:
                folder=name.rsplit('/',1)[0] if '/' in name else ''
                prefix=name.rsplit('/',1)[-1].split(' - ')[0] if geographic else ''
                chars=[n for n in members if 'caracter' in normalize(n).lower() and
                       (n.rsplit('/',1)[0] if '/' in n else '')==folder and
                       (not prefix or n.rsplit('/',1)[-1].startswith(prefix+' - '))]
                assert len(chars)==1,(name,chars)
                o=read_module(z,name)
                c=read_module(z,chars[0])
                for d in [o,c]:
                    assert all(k in d for k in KEY),(name,'missing key')
                    assert not d.duplicated(KEY).any(),(name,'duplicate person key')
                extra=[col for col in c if col not in o]
                d=o.merge(c[KEY+extra],on=KEY,how='left',validate='one_to_one',indicator=True)
                assert d._merge.eq('both').all(),(name,'unmatched characteristics')
                d=d.drop(columns='_merge')
                d['source_archive']=path.name
                d['source_module']=name
                parts.append(d)
                records.append(dict(year=year,archive=path.name,module=name,rows=len(d)))
        print(year,path.name,'loaded',flush=True)
    raw=pd.concat(parts,ignore_index=True)
    assert not raw.duplicated(KEY).any(),(year,'overlapping modules')
    assert set(raw.MES.unique())==set(range(1,13)),(year,'incomplete months',raw.MES.unique())
    pd.DataFrame(records).to_csv((manifest_dir or OUT)/f'modules_{year}.csv',index=False)
    return raw
