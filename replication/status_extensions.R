args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr); library(fixest)})
source(file.path(paper, "replication/harmonize_occupation.R"))
setFixest_nthreads(2)
out <- file.path(paper, "replication/status_output")
cache <- file.path(paper, "build/status_extensions")
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
input <- if (length(args)) args[1] else file.path(paper, "data/GEIH_primary_income_2008_2025.dta")
input_md5 <- unname(tools::md5sum(input))
provenance <- readLines(file.path(out, "provenance.txt"))
stopifnot(paste("Input MD5:",input_md5) %in% provenance)
write_csv <- function(x, name) {
  path <- file.path(out, paste0(name, ".csv"))
  if (name == "endpoint_covariances") {
    con <- gzfile(paste0(path, ".gz"), "wt")
    on.exit(close(con))
    write.csv(x, con, row.names = FALSE)
  } else write.csv(x, path, row.names = FALSE)
}
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
cols <- c("anio", "depto", "edad", "sector", "tamano_empresa", "educacion", "posicion_ocupacional",
  "posicion_ocupacional_label", "mujer", "formal", "fex", "horas", "log_ingreso_hora_real")
message("Reading current primary-income data")
d <- harmonize_occupation(read_dta(input, col_select = all_of(cols))) %>%
  mutate(across(c(anio, depto, sector, educacion), factor), edad = as.numeric(edad), edad2 = edad^2,
    tamano_empresa = factor(tamano_empresa, levels = sizes), occupation = occupation_harmonized_code,
    size_id = as.integer(tamano_empresa), osf = factor(sprintf("o%d_g%02d_f%d", occupation, size_id, formal)),
    sector_depto = interaction(sector, depto, drop = TRUE), sector_depto_year = interaction(sector, depto, anio, drop = TRUE))
counts <- tabulate(as.integer(d$sector_depto_year), nbins = nlevels(d$sector_depto_year))
d <- droplevels(d[counts[as.integer(d$sector_depto_year)] > 1L, ])
stopifnot(nrow(d) == 5426174L, !anyNA(d), all(d$horas > 0))
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
controls <- paste0("mujer + edad + edad2 + i(educacion, ref = '", edu, "')")
pooled <- readRDS(file.path(out, "models.rds"))$M2
stopifnot(pooled$n == nrow(d))

# Recover absorbed FE from weighted residual means without materializing a large dummy matrix.
b <- pooled$b
cell_value <- setNames(c(0, b[startsWith(names(b), "osf::")]),
  c("o1_g05_f1", sub("^osf::", "", names(b)[startsWith(names(b), "osf::")])))
xb <- unname(cell_value[as.character(d$osf)])
for (term in c("mujer", "edad", "edad2")) xb <- xb + b[term]*d[[term]]
for (term in names(b)[startsWith(names(b), "educacion::")]) xb <- xb + b[term]*(as.character(d$educacion) == sub("^educacion::", "", term))
stopifnot(!anyNA(xb))
fe_num <- rowsum(d$fex*(d$log_ingreso_hora_real-xb), d$sector_depto_year, reorder = FALSE)
fe_den <- rowsum(d$fex, d$sector_depto_year, reorder = FALSE)
fe <- setNames(as.numeric(fe_num/fe_den), rownames(fe_num))
eta <- xb + fe[as.character(d$sector_depto_year)]
rmse <- sqrt(weighted.mean((d$log_ingreso_hora_real-eta)^2, d$fex))
old_stats <- read.csv(file.path(out, "model_statistics.csv"))
stopifnot(abs(rmse-old_stats$weighted_rmse[old_stats$model == "M2"]) < 1e-9)
write_csv(data.frame(weighted_rmse = rmse, error = rmse-old_stats$weighted_rmse[old_stats$model == "M2"]), "prediction_check")
t <- d[as.character(d$anio) == "2025", ]
t$eta <- eta[as.character(d$anio) == "2025"]
rm(xb, eta, fe_num, fe_den); invisible(gc())
t$origin <- as.character(t$osf)
t$baseline <- exp(t$eta)*t$horas
t$observed <- exp(t$log_ingreso_hora_real)*t$horas
support <- d %>% group_by(sector, depto, occupation, size_id, formal) %>%
  summarise(npooled = n(), n2025 = sum(anio == "2025"), .groups = "drop")
key <- function(s, dep, o, g, f) paste(s, dep, o, g, f, sep = "|")
support$key <- with(support, key(sector, depto, occupation, size_id, formal))
origin <- t %>% group_by(occupation, size_id, formal, origin) %>%
  summarise(n = n(), workers = sum(fex), predicted_income = sum(fex*baseline), observed_income = sum(fex*observed), .groups = "drop")
write_csv(origin, "income_origin_aggregates")
write_csv(data.frame(n = nrow(t), workers = sum(t$fex), informal_workers = sum(t$fex[t$formal == 0]),
  predicted_income = sum(t$fex*t$baseline)), "income_population")
scenario_defs <- list(formalize_same_size = list(g = t$size_id, f = rep(1L,nrow(t))),
  formal_to_101 = list(g = ifelse(t$formal == 1, 9L, t$size_id), f = t$formal),
  informal_to_101 = list(g = ifelse(t$formal == 0, 9L, t$size_id), f = t$formal),
  combined_formal_101 = list(g = rep(9L,nrow(t)), f = rep(1L,nrow(t))))
results <- list(); diagnostics <- list(); breakdown <- list()
for (sc in names(scenario_defs)) {
  a <- scenario_defs[[sc]]
  dest <- sprintf("o%d_g%02d_f%d", t$occupation, a$g, a$f)
  move <- dest != t$origin
  stopifnot(all(dest %in% names(cell_value)))
  idx <- match(key(t$sector,t$depto,t$occupation,a$g,a$f),support$key)
  np <- ifelse(is.na(idx),0,support$npooled[idx]); nt <- ifelse(is.na(idx),0,support$n2025[idx])
  denom_w <- sum(t$fex[move])
  diagnostics[[sc]] <- data.frame(scenario = sc, intended_workers = denom_w,
    absent_pooled_pct = 100*sum(t$fex[move & np==0])/denom_w,
    absent_2025_pct = 100*sum(t$fex[move & nt==0])/denom_w,
    under30_2025_pct = 100*sum(t$fex[move & nt<30])/denom_w)
  for (rule in c("unrestricted","pooled_n30","target_n30")) {
    allow <- switch(rule,unrestricted = rep(TRUE,nrow(t)),pooled_n30 = np>=30,target_n30 = nt>=30)
    final <- ifelse(allow,dest,t$origin)
    moved <- final != t$origin
    mult <- exp(cell_value[final]-cell_value[t$origin])
    for (method in c("predicted","observed")) {
      y <- if (method == "predicted") t$baseline else t$observed
      gain <- 100*sum(t$fex*y*(mult-1))/sum(t$fex*y)
      mover_gain <- if(any(moved)) 100*sum((t$fex*y*(mult-1))[moved])/sum((t$fex*y)[moved]) else NA_real_
      # Check aggregation by origin-destination independently.
      check <- data.frame(origin=t$origin,dest=final,mass=t$fex*y) %>% group_by(origin,dest) %>% summarise(mass=sum(mass),.groups="drop")
      agg <- 100*sum(check$mass*expm1(cell_value[check$dest]-cell_value[check$origin]))/sum(check$mass)
      stopifnot(abs(agg-gain)<1e-9)
      results[[length(results)+1L]] <- data.frame(scenario=sc,support=rule,method=method,
        gain_pct=gain,mover_gain_pct=mover_gain,workers=sum(t$fex),moved_workers=sum(t$fex[moved]),
        moved_pct=100*sum(t$fex[moved])/sum(t$fex),aggregation_error=agg-gain)
    }
    if(rule=="unrestricted") breakdown[[sc]] <- t %>% mutate(mult=mult,moved=moved) %>% group_by(occupation) %>%
      summarise(workers=sum(fex),moved_workers=sum(fex[moved]),baseline_income=sum(fex*baseline),
        gain_pct=100*sum(fex*baseline*(mult-1))/sum(fex*baseline),
        contribution_pp=100*sum(fex*baseline*(mult-1))/sum(t$fex*t$baseline),.groups="drop") %>% mutate(scenario=sc)
  }
}
write_csv(bind_rows(results),"income_scenarios")
write_csv(bind_rows(diagnostics),"income_support")
write_csv(bind_rows(breakdown),"income_by_status")
message("M2 income scenarios completed")
print(bind_rows(results) %>% filter(support=="unrestricted",method=="predicted"))
rm(t,support,origin); invisible(gc())

fit_model <- function(name, rhs, dat) {
  path <- file.path(cache,paste0(name,".rds"))
  signature <- list(version=1L,md5=input_md5,rhs=rhs,n=nrow(dat),fixest=as.character(packageVersion("fixest")))
  saved <- if(file.exists(path)) readRDS(path) else NULL
  if(!is.null(saved) && identical(saved$signature,signature)) return(saved$model)
  message("Estimating ", name, " on ", nrow(dat), " observations")
  m <- feols(as.formula(paste("log_ingreso_hora_real ~",rhs)),data=dat,weights=~fex,cluster=~sector_depto,mem.clean=TRUE)
  cls <- list(`Sector-department`=~sector_depto,Sector=~sector,Department=~depto,`Sector and department`=~sector+depto)
  V <- lapply(cls,function(cl) vcov(m,vcov=cl))
  dfs <- sapply(cls,function(cl) degrees_freedom(m,"t",vcov=cl))
  ans <- list(b=coef(m),V=V,dfs=dfs,n=nobs(m),dropped=m$collin.var)
  saveRDS(list(signature=signature,model=ans),path)
  rm(m); invisible(gc()); ans
}
vec <- function(m,o,g,f,year=NULL) {
  code <- sprintf("o%d_g%02d_f%d",o,g,f)
  prefix <- if(is.null(year)) "osf::" else "cell_year::"
  if(!is.null(year)) code <- paste0("y",year,"_",code)
  z <- setNames(numeric(length(m$b)),names(m$b))
  base <- if(is.null(year)) "o1_g05_f1" else paste0("y",year,"_o1_g05_f1")
  if(code==base) return(z)
  term <- paste0(prefix,code)
  if(!term %in% names(m$b)) return(NULL)
  z[term] <- 1; z
}
diffvec <- function(m,o,g,f,ref,year=NULL) {
  a<-vec(m,o,g,f,year); b<-vec(m,o,ref,f,year)
  if(is.null(a)||is.null(b)) NULL else a-b
}
estimate <- function(m,z,cl="Sector-department") {
  if(is.null(z)) return(NULL)
  est <- sum(z*m$b); se<-sqrt(max(0,drop(t(z)%*%m$V[[cl]]%*%z))); df<-m$dfs[cl]; q<-qt(.975,df)
  data.frame(log_gap=est,se=se,p=2*pt(abs(est/se),df,lower.tail=FALSE),df=unname(df),
    premium=100*expm1(est),ci_low=100*expm1(est-q*se),ci_high=100*expm1(est+q*se))
}
rhs <- paste("i(osf, ref = 'o1_g05_f1') +",controls,"| sector_depto_year")
annual <- list(); fits <- list()
for(yr in levels(d$anio)) {
  dat <- droplevels(d[d$anio==yr,])
  m <- fit_model(paste0("year",yr),rhs,dat); fits[[yr]] <- m
  for(o in c(1:5,8:9)) for(f in 0:1) for(ref in c(1L,5L)) for(g in setdiff(1:9,ref)) {
    z<-diffvec(m,o,g,f,ref); e<-estimate(m,z)
    if(is.null(e)) next
    nref<-sum(dat$occupation==o & dat$formal==f & dat$size_id==ref)
    ndest<-sum(dat$occupation==o & dat$formal==f & dat$size_id==g)
    annual[[length(annual)+1L]]<-cbind(year=as.integer(yr),occupation=o,formal=f,reference=sizes[ref],size=sizes[g],n_origin=nref,n_destination=ndest,e)
  }
  write_csv(bind_rows(annual),"annual_profiles")
  rm(dat); invisible(gc())
}
ep<-droplevels(d[as.character(d$anio)%in%c("2008","2025"),]); rm(d); invisible(gc())
ep$post<-as.integer(ep$anio=="2025")
ep$cell_year<-factor(paste0("y",ep$anio,"_",ep$osf))
erhs<-paste0("i(cell_year,ref=c('y2008_o1_g05_f1','y2025_o1_g05_f1')) + ",controls,
  " + mujer:post + edad:post + edad2:post + i(educacion,post,ref='",edu,"') | sector_depto_year")
em<-fit_model("endpoints",erhs,ep)
changes<-list();checks<-list()
for(o in c(1:5,8:9)) for(f in 0:1) for(ref in c(1L,5L)) for(g in setdiff(1:9,ref)) {
  early<-diffvec(em,o,g,f,ref,2008);late<-diffvec(em,o,g,f,ref,2025)
  if(is.null(early)||is.null(late)) next
  for(yr in c(2008,2025)) {
    z<-if(yr==2008)early else late
    zz<-diffvec(fits[[as.character(yr)]],o,g,f,ref)
    if(is.null(zz)) next
    checks[[length(checks)+1L]]<-data.frame(year=yr,occupation=o,formal=f,reference=sizes[ref],size=sizes[g],
      error=sum(z*em$b)-sum(zz*fits[[as.character(yr)]]$b))
  }
  for(cl in names(em$V)) changes[[length(changes)+1L]]<-cbind(occupation=o,formal=f,reference=sizes[ref],size=sizes[g],clustering=cl,
    premium_2008=100*expm1(sum(early*em$b)),premium_2025=100*expm1(sum(late*em$b)),estimate(em,late-early,cl))
}
checks<-bind_rows(checks);stopifnot(max(abs(checks$error))<1e-7)
write_csv(checks,"endpoint_replication_check")
write_csv(bind_rows(changes),"endpoint_changes")
write_csv(data.frame(term=names(em$b),coefficient=em$b),"endpoint_coefficients")
cv<-bind_rows(lapply(names(em$V),function(cl){v<-as.data.frame(as.table(em$V[[cl]]));names(v)<-c("term1","term2","covariance");cbind(clustering=cl,v)}))
write_csv(cv,"endpoint_covariances")
writeLines(c(paste("Input MD5:",input_md5),paste("R:",R.version.string),paste("fixest:",packageVersion("fixest")),
  "M2 dynamics: separate annual observed status-size-formality cell intercepts and all worker-control slopes.",
  "Endpoint tests: joint 2008/2025 regression retaining cross-year cluster covariance, with four clustering procedures.",
  "M2 scenarios: same 2025 workers, weights, hours, employment status and covariates. Fixed pooled coefficients and absorbed FE.",
  "Predicted baseline reconstructed using weighted within-FE residual means and verified against pooled M2 RMSE.",
  "No unavailable pooled destination cell is assigned a coefficient. All actual 2025 destinations must exist.",
  "Support restrictions leave ineligible movers at origin and keep the entire workforce denominator.",
  "Percentage changes compare weighted predicted weekly income totals. A common retransformation factor cancels."),file.path(out,"extension_provenance.txt"))
message("PASS: M2 scenario aggregation and annual/joint endpoint equality")
