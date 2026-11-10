"""Independently reconstruct published contrasts and M2 income scenarios."""
import csv
import gzip
import json
from pathlib import Path
import numpy as np
from scipy.stats import t

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/status_output"
SIZES = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]


def read(name):
    path=OUT/(name+".csv")
    zipped=path.with_suffix(".csv.gz")
    stream=gzip.open(zipped,"rt",encoding="utf-8-sig",newline="") if zipped.exists() else path.open(encoding="utf-8-sig",newline="")
    with stream as f:
        return list(csv.DictReader(f))


coef = read("coefficients")
cov = read("covariances")
models = {}
for name in ("M0", "M1", "M2"):
    rows = [r for r in coef if r["model"] == name]
    terms = [r["term"] for r in rows]
    idx = {term: j for j, term in enumerate(terms)}
    Vs = {}
    for cl in ("Sector-department", "Sector"):
        V = np.zeros((len(terms), len(terms)))
        for r in cov:
            if r["model"] == name and r["clustering"] == cl:
                V[idx[r["term1"]], idx[r["term2"]]] = float(r["covariance"])
        assert np.max(np.abs(V-V.T)) < 1e-9
        Vs[cl] = V
    models[name] = (np.array([float(r["coefficient"]) for r in rows]), idx, Vs)


def profile(name, occupation, size, formal):
    b, idx, _ = models[name]
    z = np.zeros(len(b))
    if name == "M0":
        if size != "Solo":
            term = "tamano_empresa::"+size
            z[idx[term]] = 1
            if formal:
                matches = [a for a in (term+":formal", "formal:"+term) if a in idx]
                assert len(matches) == 1
                z[idx[matches[0]]] = 1
    else:
        code = f"o{occupation}_g{SIZES.index(size)+1:02d}"
        if name == "M2": code += f"_f{formal}"
        ref = "o1_g05" if name == "M1" else "o1_g05_f1"
        if code != ref: z[idx[("os::" if name == "M1" else "osf::")+code]] = 1
    return z


checks = 0
errors = []
for r in read("contrasts"):
    if r["log_gap"] == "NA": continue
    name = r["model"]; o = int(r["occupation"]); f = int(r["formality"] == "Formal")
    b, _, V = models[name]
    z = profile(name,o,r["size"],f)-profile(name,o,r["reference"],f)
    est = z@b; se = np.sqrt(max(0,z@V[r["clustering"]]@z)); df=float(r["df"])
    p = 2*t.sf(abs(est/se),df); q=t.ppf(.975,df)
    values={"log_gap":est,"se":se,"p":p,"premium":100*np.expm1(est),
            "ci_low":100*np.expm1(est-q*se),"ci_high":100*np.expm1(est+q*se)}
    errors.extend(abs(v-float(r[k])) for k,v in values.items())
    checks += 1
assert max(errors) < 1e-7

between = []
for ref in ("Solo", "11-19"):
    for f in (0, 1):
        b, _, Vs = models["M2"]
        z = (profile("M2",4,"101+",f)-profile("M2",4,ref,f)
             -profile("M2",1,"101+",f)+profile("M2",1,ref,f))
        for cl,df in (("Sector-department",558),("Sector",16)):
            est=z@b;se=np.sqrt(z@Vs[cl]@z)
            between.append(dict(reference=ref,formal=f,clustering=cl,
                                log_difference=est,se=se,p=2*t.sf(abs(est/se),df)))
with (OUT/"between_status_tests.csv").open("w",newline="",encoding="utf-8") as f:
    writer=csv.DictWriter(f,fieldnames=list(between[0]));writer.writeheader();writer.writerows(between)

ep = read("endpoint_coefficients")
terms = [r["term"] for r in ep]; idx={v:k for k,v in enumerate(terms)}
b = np.array([float(r["coefficient"]) for r in ep])
Vs = {}
for r in read("endpoint_covariances"):
    V=Vs.setdefault(r["clustering"],np.zeros((len(terms),len(terms))))
    V[idx[r["term1"]],idx[r["term2"]]]=float(r["covariance"])


def endpoint(o,g,f,year):
    z=np.zeros(len(terms));code=f"y{year}_o{o}_g{SIZES.index(g)+1:02d}_f{f}"
    if code != f"y{year}_o1_g05_f1": z[idx["cell_year::"+code]]=1
    return z


endpoint_errors=[]
for r in read("endpoint_changes"):
    o=int(r["occupation"]); f=int(r["formal"])
    early=endpoint(o,r["size"],f,2008)-endpoint(o,r["reference"],f,2008)
    late=endpoint(o,r["size"],f,2025)-endpoint(o,r["reference"],f,2025)
    z=late-early; est=z@b; se=np.sqrt(max(0,z@Vs[r["clustering"]]@z))
    vals={"log_gap":est,"se":se,"p":2*t.sf(abs(est/se),float(r["df"])),
          "premium_2008":100*np.expm1(early@b),"premium_2025":100*np.expm1(late@b)}
    endpoint_errors.extend(abs(v-float(r[k])) for k,v in vals.items())
assert max(endpoint_errors)<1e-7
assert max(abs(float(r["error"])) for r in read("endpoint_replication_check"))<1e-7
assert abs(float(read("prediction_check")[0]["error"]))<1e-9

origin=read("income_origin_aggregates")
scenarios=read("income_scenarios")
b,_,_=models["M2"]
income_errors=[]
for sc in ("formalize_same_size","formal_to_101","informal_to_101","combined_formal_101"):
    for method in ("predicted","observed"):
        denominator=0;change=0;mover_base=0;moved_workers=0;workers=0
        for r in origin:
            o=int(r["occupation"]);g=int(r["size_id"]);f=int(r["formal"])
            destg=9 if sc=="combined_formal_101" or (sc=="formal_to_101" and f==1) or (sc=="informal_to_101" and f==0) else g
            destf=1 if sc in ("combined_formal_101","formalize_same_size") else f
            z=profile("M2",o,SIZES[destg-1],destf)-profile("M2",o,SIZES[g-1],f)
            mass=float(r[method+"_income"]);w=float(r["workers"])
            change+=mass*np.expm1(z@b);denominator+=mass;workers+=w
            if (g,f)!=(destg,destf):mover_base+=mass;moved_workers+=w
        target=[r for r in scenarios if r["scenario"]==sc and r["support"]=="unrestricted" and r["method"]==method][0]
        for k,v in {"gain_pct":100*change/denominator,"mover_gain_pct":100*change/mover_base,
                    "moved_workers":moved_workers,"workers":workers}.items():
            income_errors.append(abs(v-float(target[k])))
assert max(income_errors)<1e-6
stats=read("model_statistics")
assert {int(r["n"]) for r in stats}=={5426174}
assert sum(int(r["n"]) for r in read("cells_pooled"))==5426174
assert len([r for r in read("cells_pooled") if int(r["n"])>0])==127
assert {r["anio"] for r in read("cells_by_year")}=={str(y) for y in range(2008,2026) if y!=2020}
result={"status":"PASS","pooled_contrasts_checked":checks,"pooled_max_error":max(errors),
        "endpoint_max_error":max(endpoint_errors),"income_max_error":max(income_errors),
        "N":5426174,"nonempty_cells":127,
        "scope":"Independent aggregate reconstruction, not a new raw-microdata reconstruction."}
(OUT/"validation.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
print(json.dumps(result,indent=2))
