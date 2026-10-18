"""Memory-bounded WLS/FWL sufficient statistics for a separate inference audit.

No manuscript outputs are changed. Each sector-department-year fixed effect
is removed by weighted centering of cross-products. Compression preserves
X'X and X'y within each sector-department cluster, not individual records.
"""
import os
os.environ["OPENBLAS_NUM_THREADS"] = "2"
os.environ["OMP_NUM_THREADS"] = "2"
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build/qa_dependencies"))
import numpy as np
import pandas as pd
from scipy.stats import t

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/inference_audit_output"
CACHE = ROOT / "build/inference_audit"
OUT.mkdir(exist_ok=True)
CACHE.mkdir(exist_ok=True)
SOURCE = ROOT.parent / "CJC-Monitor/Datos/Processed/Paper-GEIH_base_modelo_personas_2008_2025.dta"
coefs = pd.read_csv(ROOT / "replication/preferred_output/coefficients.csv")
terms = coefs.loc[coefs.model.eq("preferred"), "term"].tolist()
all_terms = terms + ["log_size", "formal:log_size"]
scales = np.ones(len(all_terms))
scales[all_terms.index("edad")] = 100
scales[all_terms.index("edad2")] = 10000
sizes = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]
midpoints = dict(zip(sizes, [1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, 150]))
occupation = ["Obrero o empleado de empresa particular", "Obrero o empleado del gobierno",
              "Empleado dom\u00e9stico", "Trabajador por cuenta propia", "Patr\u00f3n o empleador",
              "Trabajador familiar sin remuneraci\u00f3n", "Trabajador sin remuneraci\u00f3n en otros hogares",
              "Jornalero o pe\u00f3n", "Otro"]
cols = ["anio", "depto", "edad", "sector", "tamano_empresa", "educacion", "posicion_ocupacional_label",
        "mujer", "formal", "fex", "log_ingreso_hora_real"]
cache_file = CACHE / "cell_moments.npz"
signature = [SOURCE.stat().st_size, SOURCE.stat().st_mtime_ns, all_terms]
if cache_file.exists() and json.loads((CACHE / "signature.json").read_text()) == signature:
    z = np.load(cache_file)
    moments, counts = z["moments"], z["counts"]
    keys = json.loads((CACHE / "cell_keys.json").read_text())
else:
    cells = {}
    counts_map = {}
    total = 0
    with pd.read_stata(SOURCE, columns=cols, convert_categoricals=False, chunksize=100000) as reader:
        for chunk in reader:
            ok = np.isfinite(chunk.log_ingreso_hora_real) & chunk.tamano_empresa.isin(sizes)
            ok &= chunk[["mujer", "edad", "formal", "fex", "depto"]].notna().all(axis=1)
            ok &= chunk.fex.gt(0) & chunk.educacion.ne("") & chunk.sector.ne("")
            d = chunk.loc[ok].copy()
            assert not d.anio.eq(2020).any()
            modern = d.anio.ge(2021)
            raw_occ = d.posicion_ocupacional_label.copy()
            d.loc[modern & raw_occ.eq(occupation[6]), "posicion_ocupacional_label"] = occupation[7]
            d.loc[modern & raw_occ.eq(occupation[7]), "posicion_ocupacional_label"] = occupation[8]
            assert d.posicion_ocupacional_label.isin(occupation).all()
            vals = {}
            for name in all_terms:
                if name.startswith("formal:"):
                    continue
                if "::" in name:
                    variable, level = name.split("::", 1)
                    vals[name] = d[variable].eq(level).to_numpy(dtype=float)
                elif name == "edad2":
                    vals[name] = d.edad.to_numpy(dtype=float)**2
                elif name == "log_size":
                    vals[name] = np.log(d.tamano_empresa.map(midpoints).to_numpy())
                else:
                    vals[name] = d[name].to_numpy(dtype=float)
            for name in all_terms:
                if name.startswith("formal:"):
                    vals[name] = vals["formal"] * vals[name[len("formal:"):]]
            x = np.column_stack([vals[name] for name in all_terms]) / scales
            a = np.column_stack([np.ones(len(d)), x, d.log_ingreso_hora_real.to_numpy()])
            a *= np.sqrt(d.fex.to_numpy(dtype=float)/1000)[:, None]
            keyframe = d[["sector", "depto", "anio"]].reset_index(drop=True)
            for key, ix in keyframe.groupby(["sector", "depto", "anio"], sort=False).indices.items():
                key = (str(key[0]), int(key[1]), int(key[2]))
                part = a[ix]
                q = part.T @ part
                if key not in cells:
                    cells[key] = q
                    counts_map[key] = 0
                else:
                    cells[key] += q
                counts_map[key] += len(ix)
            total += len(d)
            if total // 500000 != (total-len(d)) // 500000:
                print("Processed", total, "eligible observations", flush=True)
    keys = list(cells)
    counts = np.array([counts_map[k] for k in keys])
    moments = np.stack([cells[k] for k in keys])
    np.savez(cache_file, moments=moments, counts=counts)
    (CACHE / "cell_keys.json").write_text(json.dumps(keys), encoding="utf-8")
    (CACHE / "signature.json").write_text(json.dumps(signature), encoding="utf-8")

assert counts.sum() == 5268514, counts.sum()
keep = counts > 1
assert counts[keep].sum() == 5268375
moments, counts = moments[keep], counts[keep]
keys = [k for k, take in zip(keys, keep) if take]
within = moments[:, 1:, 1:] - (moments[:, 1:, :1] @ moments[:, :1, 1:]) / moments[:, :1, :1]
basecols = np.arange(len(terms))
elasticcols = np.array([j for j, term in enumerate(all_terms) if "tamano_empresa" not in term])
checks, conventional, diagnostics, contrasts_export = [], [], [], []

def build_model(name, columns, endpoint=False):
    k = len(columns)*(2 if endpoint else 1)
    names = ([f"{y}:{all_terms[j]}" for y in [2008, 2025] for j in columns] if endpoint
             else [all_terms[j] for j in columns])
    groups = {}
    nn = {}
    for ix, (sector, dept, year) in enumerate(keys):
        if endpoint and year not in [2008, 2025]:
            continue
        key = (sector, dept)
        if key not in groups:
            groups[key] = np.zeros((k+1, k+1))
            nn[key] = 0
        block = np.r_[columns, len(all_terms)]
        target = np.r_[np.arange(len(columns)) + (len(columns) if endpoint and year == 2025 else 0), k]
        groups[key][np.ix_(target, target)] += within[ix][np.ix_(block, block)]
        nn[key] += int(counts[ix])
    group_keys = list(groups)
    q = np.stack([groups[key] for key in group_keys])
    identified = np.diag(q[:, :-1, :-1].sum(axis=0)) > 1e-9
    pick = np.r_[np.where(identified)[0], k]
    q = q[:, pick][:, :, pick]
    names = [v for v, take in zip(names, identified) if take]
    k = len(names)
    H = q[:, :-1, :-1].sum(axis=0)
    Hinv = np.linalg.inv(H)
    beta = Hinv @ q[:, :-1, -1].sum(axis=0)
    score = q[:, :-1, -1] - q[:, :-1, :-1] @ beta
    n = sum(nn.values())
    print(name, "N", n, "K", k, "clusters", len(group_keys), flush=True)
    if name == "preferred":
        old = coefs[coefs.model.eq("preferred")].set_index("term").loc[names, "estimate"].to_numpy()
        err = np.max(np.abs(beta/scales[:len(terms)]-old))
        assert err < 1e-7, err
        checks.append(dict(model=name, check="coefficients", max_error=err))
    if name == "elasticity":
        old = coefs[coefs.model.eq("elasticity_interacted")].set_index("term")
        for j, term in enumerate(names):
            oldterm = term.replace("formal:log_size", "log_size_midpoint:formal").replace("log_size", "log_size_midpoint")
            if oldterm == "log_size_midpoint_midpoint:formal":
                oldterm = "log_size_midpoint:formal"
            value = beta[j] / scales[all_terms.index(term)]
            assert abs(value-old.loc[oldterm, "estimate"]) < 1e-7, (term, oldterm)
    def unit(term):
        z = np.zeros(k)
        z[names.index(term)] = 1
        return z
    def profile(size, formal, year=None):
        prefix = f"{year}:" if year else ""
        if size == "Solo":
            return np.zeros(k)
        z = unit(prefix+"tamano_empresa::"+size)
        if formal:
            z += unit(prefix+"formal:tamano_empresa::"+size)
        return z
    tests = {}
    if endpoint:
        for f in [0, 1]:
            tests[f"{'Formal' if f else 'Informal'} change 101+/solo 2008-2025"] = profile("101+",f,2025)-profile("101+",f,2008)
    elif name == "elasticity":
        tests = {"Informal elasticity": unit("log_size"), "Formal elasticity": unit("log_size")+unit("formal:log_size"),
                 "Formal-minus-informal elasticity": unit("formal:log_size")}
    else:
        for f in [0, 1]:
            label = "Formal" if f else "Informal"
            for size in sizes[1:]:
                tests[f"{label} {size}/solo"] = profile(size, f)
            for ref in sizes[1:-1]:
                tests[f"{label} 101+/{ref}"] = profile("101+", f)-profile(ref, f)
        tests["Formal-minus-informal 101+/solo"] = profile("101+",1)-profile("101+",0)
        for size in sizes:
            tests[f"Formal-informal at {size}"] = unit("formal")+profile(size,1)-profile(size,0)
    gframe = pd.DataFrame(group_keys, columns=["sector", "depto"])
    cov = {}
    for cluster in ["Sector-department", "Sector", "Department"]:
        g = (np.arange(len(q)) if cluster == "Sector-department" else pd.factorize(gframe["sector" if cluster == "Sector" else "depto"])[0])
        G = len(np.unique(g))
        s = np.zeros((G,k)); np.add.at(s,g,score)
        factor = (n-1)/(n-k-1)*G/(G-1)
        cov[cluster] = Hinv @ (s.T@s) @ Hinv * factor
        count_group = np.bincount(g, weights=[nn[key] for key in group_keys])
        diagnostics.append(dict(model=name, clustering=cluster, G=G, n=n, smallest=count_group.min(),
                                largest=count_group.max(), largest_share=count_group.max()/n,
                                size_effective_G=n*n/(count_group@count_group)))
    gs, gd, gsd = len(set(gframe.sector)),len(set(gframe.depto)),len(q)
    # fixest defaults use the smallest cluster count in the multiway adjustment.
    cov["Two-way sector + department"] = (cov["Sector"]/(gs/(gs-1)) + cov["Department"]/(gd/(gd-1))
                                          - cov["Sector-department"]/(gsd/(gsd-1))) * min(gs,gd)/(min(gs,gd)-1)
    for cluster, V in cov.items():
        df = min(gs,gd)-1 if cluster.startswith("Two") else {"Sector":gs-1,"Department":gd-1,"Sector-department":gsd-1}[cluster]
        for label, z in tests.items():
            b = z@beta; variance = z@V@z
            assert variance > 0, (name,cluster,label,variance)
            se = np.sqrt(variance)
            conventional.append(dict(model=name, contrast=label, clustering=cluster, estimate=b, se=se,
                                     p=2*t.sf(abs(b/se),df), df=df, low=b-t.ppf(.975,df)*se, high=b+t.ppf(.975,df)*se))
    if name == "preferred":
        oldcov = pd.read_csv(ROOT / "replication/preferred_output/covariance_preferred.csv")
        for cluster in ["Sector-department","Sector"]:
            old = oldcov[oldcov.clustering.eq(cluster)].pivot(index="term1", columns="term2", values="covariance").loc[names,names].to_numpy()
            err = np.max(abs(cov[cluster]/np.outer(scales[:len(terms)],scales[:len(terms)])-old))
            assert err < 1e-7, (cluster,err)
            checks.append(dict(model=name,check=cluster+" covariance",max_error=err))
    # A square-root representation preserves all cluster-level moments needed by WCR11.
    synthetic = []
    for i, (sector, dept) in enumerate(group_keys):
        ev, U = np.linalg.eigh(q[i,:-1,:-1])
        use = ev > max(ev.max()*1e-12, 1e-12)
        X = np.sqrt(ev[use])[:,None] * U[:,use].T
        Y = (U[:,use].T @ q[i,:-1,-1]) / np.sqrt(ev[use])
        part = pd.DataFrame(X,columns=[f"v{j:02d}" for j in range(k)])
        part["y"] = Y
        part["sector"] = sector
        part["depto"] = dept
        part["sector_depto"] = i+1
        synthetic.append(part)
    synthetic = pd.concat(synthetic,ignore_index=True)
    synthetic.to_csv(CACHE/f"{name}_compressed.csv",index=False)
    X = synthetic.iloc[:,:k].to_numpy(); Y=synthetic.y.to_numpy()
    bcheck=np.linalg.solve(X.T@X,X.T@Y)
    assert np.max(abs(bcheck-beta))<1e-7
    checks.append(dict(model=name,check="compressed coefficient equivalence",max_error=np.max(abs(bcheck-beta))))
    for label,z in tests.items():
        for j in np.flatnonzero(z):
            contrasts_export.append(dict(model=name,contrast=label,term=f"v{j:02d}",weight=z[j], original_term=names[j]))
    pd.DataFrame({"term":[f"v{j:02d}" for j in range(k)],"original_term":names,"estimate":beta}).to_csv(OUT/f"{name}_coefficients.csv",index=False)
    pd.DataFrame(q[:, :-1, :-1].reshape(len(q),-1)).to_csv(CACHE/f"{name}_cluster_crossproducts.csv",index=False)

build_model("preferred", basecols)
build_model("endpoints", basecols, endpoint=True)
build_model("elasticity", elasticcols)
pd.DataFrame(conventional).to_csv(OUT/"conventional.csv",index=False)
pd.DataFrame(diagnostics).to_csv(OUT/"cluster_sizes.csv",index=False)
pd.DataFrame(checks).to_csv(OUT/"replication_checks.csv",index=False)
pd.DataFrame(contrasts_export).to_csv(OUT/"contrasts.csv",index=False)
print(pd.DataFrame(checks).to_string(index=False),flush=True)
