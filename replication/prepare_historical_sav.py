"""Extract only needed modules to ASCII filenames, with a member-level provenance log."""
from pathlib import Path
import zipfile
import sys
import re
import os
import pandas as pd

out=Path(os.environ["GEIH_RAW_DIR"]).resolve()
dest=out/'private_sav'
dest.mkdir(exist_ok=True)
records=[]
for year in map(int,sys.argv[1:]):
    for month in range(1,13):
        archive=out/f'SAV_GEIH_{year}_{month:02d}.zip'
        with zipfile.ZipFile(archive) as z:
            for domain in ['cabecera','resto']:
                for role in ['occ','char']:
                    matches=[n for n in z.namelist() if n.lower().endswith('.sav') and domain in n.lower()
                        and (bool(re.search(r'(^|/| - )ocupados',n,re.I)) if role=='occ' else 'caracter' in n.lower())]
                    assert len(matches)==1,(archive,domain,role,matches)
                    path=dest/f'{year}_{month:02d}_{domain}_{role}.sav'
                    if not path.exists():
                        path.write_bytes(z.read(matches[0]))
                    records.append(dict(year=year,month=month,domain=domain,role=role,
                        archive=str(archive),member=matches[0],path=str(path)))
    pd.DataFrame([r for r in records if r['year']==year]).to_csv(out/f'sav_manifest_{year}.csv',index=False)
    print(year,'extracted',flush=True)
