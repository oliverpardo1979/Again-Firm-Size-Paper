"""Typeset M1/M2 results from versioned aggregate outputs, without estimation."""
import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "replication/status_output"
SEC = ROOT / "Paper/sections"
SIZES = ["Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+"]
NAMES = {1: "Private-sector employees", 2: "Government employees", 3: "Domestic workers",
         4: "Own-account workers", 5: "Employers", 6: "Unpaid family workers",
         7: "Unpaid workers, other households", 8: "Day laborers", 9: "Other workers"}


def read(name):
    with (OUT / (name + ".csv")).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def one(rows, **keys):
    found = [r for r in rows if all(r[k] == str(v) for k, v in keys.items())]
    assert len(found) == 1, keys
    return found[0]


def num(x, digits=1):
    return "--" if x in (None, "NA", "") else f"{float(x):.{digits}f}"


def pv(r):
    p = float(r["p"])
    return "$<0.001$" if p < .001 else f"{p:.3f}"


def line(vals):
    return " & ".join(vals) + r" \\"


def table(file, caption, label, spec, header, rows, notes):
    text = [r"\begin{table}[htbp]", r"\centering\small", "\\caption{"+caption+"}",
            "\\label{"+label+"}", "\\begin{tabular}{"+spec+"}", r"\toprule", line(header),
            r"\midrule", *rows, r"\bottomrule", r"\end{tabular}", r"\par\vspace{0.3em}",
            r"\begin{minipage}{0.97\textwidth}\footnotesize", "Notes: "+notes,
            r"\end{minipage}", r"\end{table}", ""]
    (SEC / (file+".tex")).write_text("\n".join(text), encoding="utf-8")


C = read("contrasts")
cells = read("cells_pooled")


def contrast(o, ref, size, model="M2", f="Formal", cl="Sector-department"):
    return one(C, model=model, occupation=o, reference=ref, size=size,
               formality="Common within status" if model=="M1" else f, clustering=cl)


def reportable(r):
    return (r["premium"] != "NA" and min(float(r["n_origin"]), float(r["n_destination"])) >= 30
            and min(float(r["clusters_origin"]), float(r["clusters_destination"])) >= 10
            and not (r["reference"] == "Solo" and r["occupation"] in ("2", "5")))


def entry(r):
    if not reportable(r):
        return "--"
    star = "***" if float(r["p"]) < .01 else "**" if float(r["p"]) < .05 else "*" if float(r["p"]) < .1 else ""
    return num(r["premium"])+star


notes = (r"Percentage premiums from M1, Equation~(\ref{eq:status-size}), and M2, Equation~(\ref{eq:status-size-formality}). "
         r"M1 imposes a common size profile across formality within each employment category. M2 does not. "
         r"All use 5,426,174 observations. Standard errors are clustered by sector-department. "
         r"Dashes suppress contrasts with fewer than 30 observations or 10 sector-department clusters at either endpoint, "
         r"and solo comparisons for government employees and employers. These reporting rules do not remove observations from estimation. "
         r"* $p<0.10$, ** $p<0.05$, *** $p<0.01$.")
rows = []
for ref in ("Solo", "11-19"):
    if rows: rows.append(r"\midrule")
    rows.append(r"\multicolumn{4}{l}{\textit{101+ relative to " + ref.replace("-", "--") + r"}} \\")
    for o in (1,2,3,4,5,8,9):
        rows.append(line([NAMES[o],entry(contrast(o,ref,"101+","M1")),
                          entry(contrast(o,ref,"101+",f="Formal")),entry(contrast(o,ref,"101+",f="Informal"))]))
table("status_premiums_table", "Large-firm premiums by status in employment (\\%)", "tab:status-premiums",
      "lrrr", ["Status in employment", "M1", "M2 formal", "M2 informal"], rows, notes)

rows=[]
for o in range(1,10):
    total=sum(int(r["n"]) for r in cells if r["occupation"]==str(o))
    vals=[str(int(one(cells,occupation=o,size=g,formal=f)["n"])) for g,f in (("Solo",1),("Solo",0),("101+",1),("101+",0))]
    rows.append(line([NAMES[o],f"{total:,}",*vals]))
table("status_cells_table","Observations by status in employment and endpoint cell","tab:status-cells",
      "p{0.31\\textwidth}rrrrr",["Status in employment","Total",r"\shortstack{Solo\\formal}",r"\shortstack{Solo\\informal}",r"\shortstack{101+\\formal}",r"\shortstack{101+\\informal}"],rows,
      r"Estimation observations, not expanded worker counts, pooled over 2008--2019 and 2021--2025. "
      r"The total covers all nine sizes. Empty cells do not identify a premium. The two unpaid family observations occur in only one cell. "
      r"Government and employer solo records are retained in estimation but not used as published reference groups.")

for ref in ("Solo","11-19"):
    label="tab:status-profiles-"+ref.lower()
    content=[r"\begingroup\small",r"\begin{longtable}{lrrr}",
      "\\caption{M1 and M2 size premiums relative to "+ref.replace("-","--")+" (\\%)}\\label{"+label+r"}\\",
      r"\toprule",line(["Firm size","M1","M2 formal","M2 informal"]),r"\midrule\endfirsthead",
      r"\toprule",line(["Firm size","M1","M2 formal","M2 informal"]),r"\midrule\endhead",
      r"\bottomrule\endfoot"]
    for o in (1,2,3,4,5,8,9):
        content.append(r"\multicolumn{4}{l}{\textit{"+NAMES[o]+r"}}\\*")
        group_rows = []
        for size in SIZES:
            if size==ref: continue
            group_rows.append([size,entry(contrast(o,ref,size,"M1")),entry(contrast(o,ref,size,f="Formal")),entry(contrast(o,ref,size,f="Informal"))])
        if all(all(v=="--" for v in row[1:]) for row in group_rows):
            content.append(r"\multicolumn{4}{l}{Comparisons not reported under the cell rules.}\\")
        else:
            content.extend(line(row)+(r"*" if j<len(group_rows)-1 else "") for j,row in enumerate(group_rows))
        content.append(r"\addlinespace")
    content.extend([r"\end{longtable}",r"\noindent\footnotesize Notes: "+notes,r"\endgroup",""])
    (SEC/("status_profiles_"+ref.lower()+"_table.tex")).write_text("\n".join(content),encoding="utf-8")

rows=[]
for o,ref in ((1,"Solo"),(4,"Solo"),(1,"11-19"),(4,"11-19"),(2,"11-19"),(5,"11-19"),(8,"Solo")):
    for f in ("Formal","Informal"):
        r=contrast(o,ref,"101+",f=f); s=contrast(o,ref,"101+",f=f,cl="Sector")
        if reportable(r): rows.append(line([NAMES[o],ref,f,num(r["premium"]),pv(r),pv(s)]))
table("status_clustering_table","M2 large-firm contrasts under alternative clustering","tab:status-clustering",
      "l ll rrr",["Status","Reference","Formality",r"Premium (\%)","$p$ (SD)","$p$ (S)"],rows,
      r"SD denotes sector-department clustering and S denotes sector clustering. Coefficients and samples do not change. "
      r"Day laborers are concentrated in agriculture. Their reference cells span very few sectors, limiting the informativeness of sector-clustered inference.")

S=read("income_scenarios"); P=read("income_population")[0]
SC={"formalize_same_size":"Informal to formal, same size","formal_to_101":"Formal to formal 101+",
    "informal_to_101":"Informal to informal 101+","combined_formal_101":"All workers to formal 101+"}
rows=[]
for sc,label in SC.items():
    r=one(S,scenario=sc,support="unrestricted",method="predicted")
    if sc=="combined_formal_101":rows.append(r"\midrule")
    rows.append(line([label,f'{float(r["moved_workers"])/1e6:.2f}',num(r["mover_gain_pct"]),num(r["gain_pct"])]))
table("income_counterfactuals_2025_table","Illustrative income changes under M2, 2025","tab:income-counterfactuals-2025",
      "p{0.38\\textwidth}rrr",["Assignment",r"\shortstack{Reassigned\\workers\\(millions)}",r"\shortstack{Reassigned workers\\Mean income\\change (\%)}",r"\shortstack{All workers\\Total income\\change (\%)}"],rows,
      r"Equation~(\ref{eq:income-counterfactual}) with pooled M2 coefficients. The sample represents "
      +f'{float(P["workers"])/1e6:.2f} million workers. '+
      r"Income is predicted weekly labor income. Hours, employment category, other covariates, coefficients, and fixed effects are unchanged. "
      r"Workers already at the destination are not counted as reassigned. The common retransformation factor cancels.")
rows=[]
for sc,label in SC.items():
    p=one(S,scenario=sc,support="unrestricted",method="predicted");o=one(S,scenario=sc,support="unrestricted",method="observed")
    rows.append(line([label,num(p["gain_pct"]),num(o["gain_pct"])]))
table("income_counterfactual_sensitivity_table","M2 scenarios under alternative income baselines","tab:income-counterfactual-sensitivity",
      "lrr",["Assignment","Predicted baseline", "Observed baseline"],rows,
      r"Percentage changes in weekly labor income across all workers. Both columns apply M2 destination-to-origin wage ratios. "
      r"The observed baseline preserves each worker's log-income residual.")
rows=[]
SUP=read("income_support")
for sc,label in SC.items():
    r=one(SUP,scenario=sc)
    rows.append(line([label,num(r["absent_2025_pct"]),num(one(S,scenario=sc,support="unrestricted",method="predicted")["gain_pct"]),
      num(one(S,scenario=sc,support="pooled_n30",method="predicted")["gain_pct"]),num(one(S,scenario=sc,support="target_n30",method="predicted")["gain_pct"])]))
table("income_counterfactual_support_table","M2 scenarios and destination-cell support","tab:income-counterfactual-support",
      "p{0.36\\textwidth}rrrr",["Assignment",r"\shortstack{No destination\\in 2025 (\%)}",r"\shortstack{Unrestricted\\gain (\%)}",r"\shortstack{Pooled\\$n\geq30$\\gain (\%)}",r"\shortstack{2025\\$n\geq30$\\gain (\%)}"],rows,
      r"Destination cells combine sector, department, status in employment, firm size, and formality. "
      r"The first column is the percentage of intended movers with no observed destination cell in 2025. "
      r"The remaining columns are changes in total predicted weekly income across all workers. "
      r"Restricted scenarios keep workers at origin if the destination fails the stated count. Coefficients and the workforce denominator remain unchanged.")
rows=[]
for r in read("income_by_status"):
    if r["scenario"]=="combined_formal_101":
        rows.append(line([NAMES[int(r["occupation"] )],f'{float(r["workers"])/1e6:.2f}',num(r["gain_pct"]),num(r["contribution_pp"])]))
table("status_income_contributions_table","Employment categories in the joint M2 assignment","tab:status-income-contributions",
      "lrrr",["Status in employment", "Workers (millions)",r"\shortstack{Group income\\change (\%)}",r"\shortstack{Contribution to\\total change (pp)}"],rows,
      r"All workers are assigned to formal 101+ within their original status in employment. Group changes include workers not reassigned. "
      r"Contributions use each group's baseline predicted income share and sum to the change across all workers.")

if (OUT/"endpoint_changes.csv").exists():
    E=read("endpoint_changes")
    annual=read("annual_profiles")
    rows=[]
    for ref in ("Solo","11-19"):
        if rows: rows.append(r"\midrule")
        rows.append(r"\multicolumn{6}{l}{\textit{101+ relative to "+ref.replace("-","--")+r"}}\\")
        for o in (1,4):
            for f in (1,0):
                r=one(E,occupation=o,formal=f,reference=ref,size="101+",clustering="Sector-department")
                thin = o==1 and f==1 and ref=="Solo"
                vals=(["--"]*4 if thin else [num(r["premium_2008"]),num(r["premium_2025"]),
                  f'{float(r["premium_2025"])-float(r["premium_2008"]):.1f}',pv(r)])
                rows.append(line([NAMES[o],"Formal" if f else "Informal",*vals]))
    table("status_endpoint_table","M2 large-firm premiums under two references, 2008 and 2025","tab:status-endpoints",
          "llrrrr",["Status","Formality",r"2008 (\%)",r"2025 (\%)","Change (pp)","$p$-value"],rows,
          r"Equation~(\ref{eq:preferred-dynamics}). Changes in percentage points are computed before rounding. "
          r"Two-sided tests compare endpoint log-wage contrasts using joint estimation and sector-department clustering. "
          r"The formal private-employee solo comparison is omitted because its 2008 reference cell contains only eight observations.")
    rows=[]
    for o,ref in ((1,"Solo"),(1,"11-19"),(4,"Solo"),(4,"11-19"),(2,"11-19"),(5,"11-19"),(8,"Solo")):
        for f in (1,0):
            matches=[r for r in E if r["occupation"]==str(o) and r["formal"]==str(f) and r["reference"]==ref and r["size"]=="101+"]
            if len(matches)!=4:continue
            r=one(matches,clustering="Sector-department")
            endpoints=[one(annual,year=yr,occupation=o,formal=f,reference=ref,size="101+") for yr in (2008,2025)]
            thin=any(min(float(a["n_origin"]),float(a["n_destination"]))<30 for a in endpoints)
            values=(["--"]*6 if thin else [num(r["premium_2008"]),num(r["premium_2025"]),
              *[pv(one(matches,clustering=cl)) for cl in ("Sector-department","Sector","Department","Sector and department")]])
            rows.append(line([NAMES[o],ref,"F" if f else "I",*values]))
    table("status_endpoint_clustering_table","M2 endpoint tests by employment category and clustering","tab:status-endpoint-clustering",
          ">{\\raggedright\\arraybackslash}p{0.24\\textwidth}llrrrrrr",["Status","Ref.","F/I", "2008", "2025", "$p$ SD", "$p$ S", "$p$ D", "$p$ S+D"],rows,
          r"Premiums are percentages for 101+ relative to the indicated size within each status and formality group. F denotes formal and I informal. "
          r"All $p$-values test equality of endpoint log-wage contrasts. SD, S, D, and S+D denote sector-department, sector, department, "
          r"and two-way sector and department clustering. These are pointwise tests. Dashes mark comparisons with fewer than 30 observations "
          r"in any reference or destination cell in either year. Formal private employees have only eight solo observations in 2008. "
          r"In 2025, 101+ includes only 9 formal and 3 informal employers, "
          r"7 informal government employees, and 15 informal day laborers. Formal day laborers have only 16 solo observations in 2008 and 17 in 2025. "
          r"All estimates and cell counts remain available in the replication files.")
print("M1/M2 tables generated from aggregate CSV files.")
