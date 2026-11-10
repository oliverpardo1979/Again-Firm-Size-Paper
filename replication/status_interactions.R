args <- commandArgs(trailingOnly = TRUE)
resume <- FALSE
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
out <- file.path(paper, "replication/status_output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr); library(fixest)})
source(file.path(paper, "replication/harmonize_occupation.R"))
setFixest_nthreads(2)
Sys.setenv(OMP_NUM_THREADS = 2, OPENBLAS_NUM_THREADS = 2, MKL_NUM_THREADS = 2)
input <- if (length(args)) args[1] else file.path(paper, "data/GEIH_primary_income_2008_2025.dta")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
labels <- c("Private-company employee", "Government employee", "Domestic worker", "Own-account worker",
  "Employer", "Unpaid family worker", "Unpaid worker in another household", "Day laborer", "Other")
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
cols <- c("anio", "depto", "edad", "sector", "tamano_empresa", "educacion", "posicion_ocupacional",
  "posicion_ocupacional_label", "mujer", "formal", "fex", "log_ingreso_hora_real")
message("Reading adopted main-job income data")
d <- read_dta(input, col_select = all_of(cols))
stopifnot(identical(attr(d, "label"), "GEIH primary income 2026-10-21, aligned occupation codes"))
d <- harmonize_occupation(d) %>%
  mutate(across(c(anio, depto, sector, educacion, posicion_ocupacional_label), factor),
    edad = as.numeric(edad), edad2 = edad^2, tamano_empresa = factor(tamano_empresa, levels = sizes),
    occ = factor(occupation_harmonized_code)) %>%
  mutate(sector_depto = interaction(sector, depto, drop = TRUE),
    sector_depto_year = interaction(sector, depto, anio, drop = TRUE))
stopifnot(nrow(d) == 5426316L, !anyNA(d), all(d$fex > 0), !any(as.character(d$anio) == "2020"))
nn <- tabulate(as.integer(d$sector_depto_year), nbins = nlevels(d$sector_depto_year))
d <- droplevels(d[nn[as.integer(d$sector_depto_year)] > 1L, ])
stopifnot(nrow(d) == 5426174L)
d$size_id <- as.integer(d$tamano_empresa)
d$occupation <- d$occupation_harmonized_code
d$os <- factor(sprintf("o%d_g%02d", d$occupation, d$size_id))
d$osf <- factor(sprintf("o%d_g%02d_f%d", d$occupation, d$size_id, d$formal))
message("Auditing all size-status-formality cells for the full period")
cell_obs <- d %>% group_by(occupation, size_id, formal) %>% summarise(n = n(), years = n_distinct(anio),
  clusters_sd = n_distinct(sector_depto), clusters_sector = n_distinct(sector),
  weight_sum = sum(fex), kish_n = sum(fex)^2/sum(fex^2), .groups = "drop")
grid <- expand.grid(occupation = 1:9, size_id = 1:9, formal = 0:1)
cells <- left_join(grid, cell_obs, by = c("occupation", "size_id", "formal")) %>%
  mutate(across(c(n, years, clusters_sd, clusters_sector, weight_sum, kish_n), ~coalesce(.x, 0)),
    status = labels[occupation], size = sizes[size_id],
    diagnostic = case_when(n == 0 ~ "Empty", n < 30 ~ "Under 30 observations",
      clusters_sd < 10 ~ "Under 10 sector-department clusters", TRUE ~ "No small-cell flag"))
write_csv(cells, "cells_pooled")
annual <- d %>% group_by(anio, occupation, size_id, formal) %>%
  summarise(n = n(), workers = sum(fex), .groups = "drop")
write_csv(annual, "cells_by_year")
fe_cells <- d %>% group_by(sector_depto_year, occupation, size_id, formal) %>%
  summarise(n = n(), .groups = "drop")
private_out <- file.path(paper, "build/status_private")
dir.create(private_out, recursive = TRUE, showWarnings = FALSE)
write.csv(fe_cells, file.path(private_out, "cells_by_fixed_effect.csv"), row.names = FALSE)
os_cells <- d %>% group_by(occupation, size_id) %>% summarise(n = n(), years = n_distinct(anio),
  clusters_sd = n_distinct(sector_depto), clusters_sector = n_distinct(sector), .groups = "drop")
write_csv(os_cells, "status_size_cells")
status_totals <- d %>% group_by(occupation) %>% summarise(n = n(), workers_2025 = sum(fex[anio == "2025"]),
  formal_share = sum(fex*formal)/sum(fex), size_categories = n_distinct(size_id), .groups = "drop")
write_csv(left_join(data.frame(occupation = 1:9, status = labels), status_totals, by = "occupation"), "status_totals")
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1L)
controls <- paste0("mujer + edad + edad2 + i(educacion, ref = '", edu, "')")
specs <- list(
  M0 = paste("i(tamano_empresa, ref = 'Solo') * formal + i(posicion_ocupacional_label) +", controls, "| sector_depto_year"),
  M1 = paste("i(os, ref = 'o1_g05') + i(occ, formal) +", controls, "| sector_depto_year"),
  M2 = paste("i(osf, ref = 'o1_g05_f1') +", controls, "| sector_depto_year"))
models <- list(); stats <- list(); all_coef <- list(); all_cov <- list()
if (resume) {
  models <- readRDS(file.path(out, "models.rds"))
  stopifnot(identical(names(models), names(specs)),
    all(vapply(models, function(m) m$n == nrow(d), logical(1))),
    all(vapply(names(specs), function(k) identical(models[[k]]$rhs, specs[[k]]), logical(1))))
  message("Resuming contrast extraction from this run's completed, checked fits")
}
for (name in if (resume) character(0) else names(specs)) {
  message("Estimating ", name)
  start <- Sys.time()
  m <- feols(as.formula(paste("log_ingreso_hora_real ~", specs[[name]])), data = d,
    weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE)
  stopifnot(nobs(m) == nrow(d))
  a <- list(b = coef(m), V = vcov(m), V_sector = vcov(m, cluster = ~sector),
    df = degrees_freedom(m, "t"), df_sector = degrees_freedom(m, "t", vcov = ~sector),
    n = nobs(m), dropped = m$collin.var, rhs = specs[[name]],
    os_levels = levels(d$os), osf_levels = levels(d$osf), reference = if (name == "M1") "o1_g05" else "o1_g05_f1")
  models[[name]] <- a
  stats[[name]] <- data.frame(model = name, n = nobs(m), coefficients = length(coef(m)),
    r2 = unname(fitstat(m, "r2")[[1]]), within_r2 = unname(fitstat(m, "wr2")[[1]]),
    weighted_rmse = sqrt(sum(d$fex*m$residuals^2)/sum(d$fex)),
    seconds = as.numeric(difftime(Sys.time(), start, units = "secs")),
    dropped = paste(m$collin.var, collapse = ";"))
  all_coef[[name]] <- data.frame(model = name, term = names(a$b), coefficient = unname(a$b))
  for (cl in c("Sector-department", "Sector")) {
    v <- as.data.frame(as.table(if (cl == "Sector") a$V_sector else a$V), stringsAsFactors = FALSE)
    names(v) <- c("term1", "term2", "covariance")
    all_cov[[length(all_cov)+1L]] <- cbind(model = name, clustering = cl, v)
  }
  rm(m); invisible(gc())
  saveRDS(models, file.path(out, "models.rds"))
  write_csv(bind_rows(stats), "model_statistics")
  write_csv(bind_rows(all_coef), "coefficients")
  write_csv(bind_rows(all_cov), "covariances")
  message("Completed ", name)
}

old <- readRDS(file.path(paper, "replication/preferred_output/aggregate_models.rds"))$preferred
baseline_check <- data.frame(coef_error = max(abs(models$M0$b[names(old$b)]-old$b)),
  vcov_error = max(abs(models$M0$V[names(old$b), names(old$b)]-old$V)),
  sector_vcov_error = max(abs(models$M0$V_sector[names(old$b), names(old$b)]-old$V_sector)),
  n_error = models$M0$n-old$n)
stopifnot(max(abs(as.matrix(baseline_check))) < 1e-7)
write_csv(baseline_check, "baseline_replication_check")

unit <- function(m, term) {
  if (!term %in% names(m$b)) return(NULL)
  z <- setNames(numeric(length(m$b)), names(m$b)); z[term] <- 1; z
}
zero <- function(m) setNames(numeric(length(m$b)), names(m$b))
profile <- function(name, o, g, f, m = models[[name]]) {
  if (name == "M0") {
    if (g == 1L) return(zero(m))
    z <- unit(m, paste0("tamano_empresa::", sizes[g]))
    if (f == 1L) {
      term <- paste0("tamano_empresa::", sizes[g])
      it <- intersect(c(paste0(term, ":formal"), paste0("formal:", term)), names(m$b))
      stopifnot(length(it) == 1L)
      z <- z + unit(m, it)
    }
    return(z)
  }
  code <- if (name == "M1") sprintf("o%d_g%02d", o, g) else sprintf("o%d_g%02d_f%d", o, g, f)
  lv <- if (name == "M1") m$os_levels else m$osf_levels
  if (!code %in% lv) return(NULL)
  if (code == m$reference) return(zero(m))
  unit(m, paste0(if (name == "M1") "os::" else "osf::", code))
}
contrast <- function(m, z, clustering) {
  if (is.null(z)) return(data.frame(log_gap = NA_real_, se = NA_real_, df = NA_real_, p = NA_real_,
    premium = NA_real_, ci_low = NA_real_, ci_high = NA_real_))
  V <- if (clustering == "Sector") m$V_sector else m$V
  df <- if (clustering == "Sector") m$df_sector else m$df
  stopifnot(length(z) == length(m$b), !anyNA(z))
  b <- sum(z*m$b); se <- sqrt(drop(t(z) %*% V %*% z)); cv <- qt(.975, df)
  data.frame(log_gap = b, se = se, df = df, p = 2*pt(abs(b/se), df, lower.tail = FALSE),
    premium = 100*expm1(b), ci_low = 100*expm1(b-cv*se), ci_high = 100*expm1(b+cv*se))
}
support <- function(o, g, f) {
  x <- if (is.na(f)) os_cells[os_cells$occupation == o & os_cells$size_id == g, ] else
    cells[cells$occupation == o & cells$size_id == g & cells$formal == f, ]
  if (!nrow(x)) return(c(n = 0, clusters = 0, years = 0))
  c(n = x$n[1], clusters = x$clusters_sd[1], years = x$years[1])
}
rows <- list()
for (name in names(models)) for (o in if (name == "M0") 0 else 1:9) {
  for (f in if (name == "M1") NA_integer_ else 0:1) for (ref in c(1L, 5L)) for (g in setdiff(1:9, ref)) {
    a <- profile(name, o, g, f); b <- profile(name, o, ref, f)
    z <- if (is.null(a) || is.null(b)) NULL else a-b
    s <- if (name == "M0") c(n = NA, clusters = NA, years = NA) else support(o, g, f)
    r <- if (name == "M0") c(n = NA, clusters = NA, years = NA) else support(o, ref, f)
    flag <- if (name == "M0") "Common profile across statuses" else if (s['n'] == 0 || r['n'] == 0) "Empty endpoint" else
      if (is.null(z)) "Collinear contrast" else if (min(s['n'], r['n']) < 30) "Under 30 observations at endpoint" else
      if (min(s['clusters'], r['clusters']) < 10) "Under 10 clusters at endpoint" else "No small-cell flag"
    for (cl in c("Sector-department", "Sector")) rows[[length(rows)+1L]] <- cbind(
      model = name, occupation = o, status = if (o == 0) "Common profile" else labels[o],
      formality = if (is.na(f)) "Common within status" else if (f) "Formal" else "Informal",
      reference = sizes[ref], size = sizes[g], clustering = cl,
      n_origin = unname(r['n']), n_destination = unname(s['n']),
      clusters_origin = unname(r['clusters']), clusters_destination = unname(s['clusters']),
      flag = flag, contrast(models[[name]], z, cl))
  }
}
write_csv(bind_rows(rows), "contrasts")
diffs <- list()
for (o in 1:9) for (ref in c(1L, 5L)) {
  p <- lapply(list(c(9L, 1L), c(ref, 1L), c(9L, 0L), c(ref, 0L)), function(x) profile("M2", o, x[1], x[2]))
  z <- if (any(vapply(p, is.null, logical(1)))) NULL else p[[1]]-p[[2]]-p[[3]]+p[[4]]
  for (cl in c("Sector-department", "Sector")) diffs[[length(diffs)+1L]] <- cbind(occupation = o,
    status = labels[o], reference = sizes[ref], clustering = cl, contrast(models$M2, z, cl))
}
write_csv(bind_rows(diffs), "formal_minus_informal_101_contrasts")

# A second normalization verifies that empty cells and aliases are not silently
# interpreted as zero premiums. This is the same M2 specification, not a new model.
message("Checking M2 with a different reference cell")
alt_rhs <- sub("o1_g05_f1", "o1_g09_f1", specs$M2, fixed = TRUE)
alt <- feols(as.formula(paste("log_ingreso_hora_real ~", alt_rhs)), data = d,
  weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE)
am <- list(b = coef(alt), V = vcov(alt), df = degrees_freedom(alt, "t"),
  reference = "o1_g09_f1", osf_levels = levels(d$osf))
rebase <- list()
for (o in 1:9) for (f in 0:1) for (ref in c(1L, 5L)) for (g in setdiff(1:9, ref)) {
  a <- profile("M2", o, g, f); b <- profile("M2", o, ref, f)
  aa <- profile("M2", o, g, f, am); bb <- profile("M2", o, ref, f, am)
  if (any(vapply(list(a, b, aa, bb), is.null, logical(1)))) next
  x <- contrast(models$M2, a-b, "Sector-department"); y <- contrast(am, aa-bb, "Sector-department")
  rebase[[length(rebase)+1L]] <- data.frame(occupation = o, formal = f, size = sizes[g], reference = sizes[ref],
    coefficient_error = x$log_gap-y$log_gap, se_error = x$se-y$se)
}
rebase <- bind_rows(rebase)
stopifnot(max(abs(rebase$coefficient_error), abs(rebase$se_error)) < 1e-7)
write_csv(rebase, "reference_invariance_check")
rm(alt, d); invisible(gc())
writeLines(c(paste("Run:", Sys.time()), paste("Input:", basename(input)), paste("Input MD5:", unname(tools::md5sum(input))),
  paste("R:", R.version.string), paste("fixest:", packageVersion("fixest")),
  "All models use the same 5,426,174 observations from 2008-2019 and 2021-2025.",
  "M0: existing full-sample preferred model, size x formality plus status level indicators.",
  "M1: unrestricted status x size cell intercepts and status-specific formal level differences.",
  "M1 imposes a common size profile across formality within each status. M0 and M1 are not nested.",
  "M2: unrestricted observed status x size x formality cell intercepts, including all lower-order terms.",
  "M2 nests M0 and M1. All models retain common worker-control slopes and sector-department-year fixed effects.",
  "Cell-intercept parameterization is equivalent to the requested categorical interactions on observed cells.",
  "Empty cells are not estimated. Flags at N<30 or fewer than 10 clusters are descriptive warnings, not deletion rules or guarantees of precision.",
  "No observations or statuses are dropped beyond the current preferred model's FE singletons.",
  "This script estimates pooled M0, M1, and M2. Run status_extensions.R for M2 dynamics and income scenarios."), file.path(out, "provenance.txt"))
print(if (resume) read.csv(file.path(out, "model_statistics.csv")) else bind_rows(stats))
message("PASS: baseline reproduction and M2 reference invariance")
