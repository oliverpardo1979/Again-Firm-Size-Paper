args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
source(file.path(paper, "replication/harmonize_occupation.R"))
cjc <- file.path(dirname(paper), "CJC-Monitor")
input <- if (length(args)) args[1] else file.path(paper, "data/GEIH_primary_income_2008_2025.dta")
out <- file.path(paper, "replication/regression_output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr); library(fixest)})
setFixest_nthreads(4)
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
cols <- c("anio", "depto", "edad", "sector", "tamano_empresa", "educacion", "posicion_ocupacional_label", "mujer", "formal", "fex", "log_ingreso_hora_real")
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
prepare <- function(path) {
  d <- harmonize_occupation(read_dta(path, col_select = all_of(cols)))
  message("Read ", nrow(d), " rows from ", basename(path))
  d %>% mutate(row_id = row_number(), across(c(anio, depto, sector, educacion, posicion_ocupacional_label), factor),
    edad = as.numeric(edad), edad2 = edad^2, tamano_empresa = factor(tamano_empresa, levels = sizes)) %>%
    filter(is.finite(log_ingreso_hora_real), !is.na(tamano_empresa), !is.na(mujer), is.finite(edad),
      !is.na(educacion), !is.na(formal), !is.na(sector), !is.na(anio), is.finite(fex), fex > 0) %>%
    mutate(sector_year = interaction(sector, anio, drop = TRUE),
      depto_year = interaction(depto, anio, drop = TRUE),
      sector_depto = interaction(sector, depto, drop = TRUE),
      sector_depto_year = interaction(sector, depto, anio, drop = TRUE),
      year_trend = as.integer(as.character(anio)) - 2008,
      log_size_midpoint = log(c(1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, 150)[as.integer(tamano_empresa)]),
      log_size_midpoint_sq = log_size_midpoint^2)
}
cache_path <- file.path(paper, "build/regression_sample.rds")
cache_signature <- list(file.info(input)$size, as.numeric(file.info(input)$mtime), occupation_harmonization_version)
d <- if (file.exists(cache_path)) readRDS(cache_path) else NULL
if (is.null(d) || !identical(attr(d, "cache_signature"), cache_signature)) {
  d <- prepare(input)
  attr(d, "cache_signature") <- cache_signature
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(d, cache_path, compress = FALSE)
}
stopifnot(!anyNA(d$depto), !anyNA(d$posicion_ocupacional_label), !any(as.character(d$anio) == "2020"))
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1)
controls <- paste0("mujer + edad + edad2 + i(educacion, ref = '", edu, "')")
size_rhs <- "i(tamano_empresa, ref = 'Solo')"
interacted_rhs <- paste(size_rhs, "* formal +", controls)
models <- list()
hash_rows <- function(x) {
  path <- tempfile()
  on.exit(unlink(path))
  writeBin(as.integer(x), path)
  unname(tools::md5sum(path))
}
fit_model <- function(name, rhs, data = d, cluster = ~sector) {
  cache_dir <- file.path(paper, "build/reconciled_models")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_file <- file.path(cache_dir, paste0(name, ".rds"))
  key <- list(signature = cache_signature, rhs = rhs, cluster = deparse(cluster),
    rows = hash_rows(data$row_id))
  cached <- if (file.exists(cache_file)) readRDS(cache_file) else NULL
  if (!is.null(cached) && identical(cached$key, key)) {
    models[[name]] <<- cached$model
    message("Reusing ", name)
    return(invisible(cached$model))
  }
  message("Estimating ", name)
  m <- feols(as.formula(paste("log_ingreso_hora_real ~", rhs)), data = data,
    weights = ~fex, cluster = cluster)
  ans <- list(b = coef(m), V = vcov(m), n = nobs(m), r2 = unname(fitstat(m, "r2")[[1]]),
    df = degrees_freedom(m, "t"), rhs = rhs, cluster = deparse(cluster),
    sample_hash = hash_rows(data$row_id[obs(m)]))
  models[[name]] <<- ans
  saveRDS(list(key = key, model = ans), cache_file)
  invisible(ans)
}
unit <- function(m, term) {
  z <- setNames(numeric(length(m$b)), names(m$b))
  stopifnot(term %in% names(z))
  z[term] <- 1
  z
}
profile <- function(m, size, formal = 0, interaction = TRUE, trend = FALSE) {
  z <- setNames(numeric(length(m$b)), names(m$b))
  if (size == "Solo") return(z)
  term <- paste0("tamano_empresa::", size)
  if (trend) term <- paste0(term, ":year_trend")
  z <- unit(m, term)
  if (formal == 1 && interaction) {
    it <- intersect(c(paste0("formal:", term), paste0(term, ":formal")), names(m$b))
    stopifnot(length(it) == 1)
    z <- z + unit(m, it)
  }
  z
}
contrast <- function(m, z) {
  b <- sum(z * m$b)
  se <- sqrt(drop(t(z) %*% m$V %*% z))
  p <- 2 * pt(abs(b/se), df = m$df, lower.tail = FALSE)
  critical <- qt(.975, df = m$df)
  data.frame(estimate = b, std.error = se, p.value = p, conf.low = b-critical*se,
    conf.high = b+critical*se, premium = 100*expm1(b), ci_low = 100*expm1(b-critical*se),
    ci_high = 100*expm1(b+critical*se), df = m$df)
}
common_rhs <- c(size_rhs, paste(size_rhs, "| sector_year"),
  paste(size_rhs, "+", controls, "| sector_year"), paste(size_rhs, "+", controls, "+ formal | sector_year"))
for (j in 1:4) fit_model(paste0("common", j), common_rhs[j])
fit_model("simple", paste(interacted_rhs, "| sector_year"))
geo_fe <- c("sector_year", "sector_year + depto_year", "sector_depto_year", "sector_depto_year")
for (j in 1:4) {
  occ <- if (j == 4) "+ i(posicion_ocupacional_label)" else ""
  fit_model(paste0("geo_common", j), paste(size_rhs, "+", controls, "+ formal", occ, "|", geo_fe[j]), cluster = ~sector_depto)
  fit_model(paste0("geo_interacted", j), paste(interacted_rhs, occ, "|", geo_fe[j]), cluster = ~sector_depto)
}
stopifnot(max(abs(models$simple$b - models$geo_interacted1$b)) < 1e-10,
  max(abs(models$common4$b - models$geo_common1$b)) < 1e-10)
fit_model("trend", paste(size_rhs, "+ i(tamano_empresa, year_trend, ref = 'Solo') +", controls, "+ formal | sector_year"))
fit_model("dynamic", paste("i(anio, tamano_empresa, ref2 = 'Solo') +", controls, "+ formal | sector_year"))
for (yr in levels(d$anio)) fit_model(paste0("year", yr), paste(interacted_rhs, "| sector"), data = d[d$anio == yr, ])
for (kind in c("elasticity", "polynomial")) {
  base <- if (kind == "elasticity") "log_size_midpoint" else "log_size_midpoint + log_size_midpoint_sq"
  fit_model(paste0(kind, "_raw"), base)
  fit_model(paste0(kind, "_full"), paste(base, "+", controls, "+ formal | sector_year"))
  for (f in 0:1) fit_model(paste0(kind, if (f == 1) "_formal" else "_informal"),
    paste(base, "+", controls, "| sector_year"), data = d[d$formal == f, ])
}

# A single fit supplies every normalization, so reference changes cannot change a contrast.
rows <- list()
for (name in c(paste0("common", 1:4), paste0("geo_common", 1:4), paste0("geo_interacted", 1:4), "simple", "trend")) {
  m <- models[[name]]
  interacted <- name == "simple" || grepl("geo_interacted", name)
  for (ref in c("Solo", "101+", "11-19")) for (sz in setdiff(sizes, ref)) {
    ci <- profile(m, sz, interaction = interacted, trend = name == "trend") - profile(m, ref, interaction = interacted, trend = name == "trend")
    cs <- list(common = ci)
    if (interacted) {
      cf <- profile(m, sz, 1) - profile(m, ref, 1)
      cs <- list(informal = ci, interaction = cf-ci, formal = cf)
    }
    for (param in names(cs)) rows[[length(rows)+1L]] <- cbind(model = name, reference = ref, size = sz, parameter = param, contrast(m, cs[[param]]))
  }
}
est <- bind_rows(rows)
write_csv(est, "contrasts")
gaps <- bind_rows(lapply(c("simple", "geo_interacted4"), function(name) {
  m <- models[[name]]
  bind_rows(lapply(sizes, function(sz) cbind(model = name, size = sz,
    contrast(m, unit(m, "formal") + profile(m, sz, 1) - profile(m, sz, 0)))))
}))
write_csv(gaps, "formal_informal_gaps")
large <- bind_rows(lapply(setdiff(sizes, "101+"), function(sz) cbind(size = sz,
  contrast(models$simple, profile(models$simple, "101+", 1) - profile(models$simple, sz, 1)))))
write_csv(large, "formal_101_contrasts")
annual <- list()
for (yr in levels(d$anio)) for (sz in sizes[-1]) {
  term <- paste0("anio::", yr, ":tamano_empresa::", sz)
  annual[[length(annual)+1L]] <- cbind(year = as.integer(yr), size = sz, group = "Common",
    contrast(models$dynamic, unit(models$dynamic, term)))
  m <- models[[paste0("year", yr)]]
  for (f in 0:1) annual[[length(annual)+1L]] <- cbind(year = as.integer(yr), size = sz,
    group = if (f) "Formal" else "Informal", contrast(m, profile(m, sz, f)))
}
write_csv(bind_rows(annual), "annual_profiles")
polynomial <- bind_rows(lapply(c("raw", "full", "formal", "informal"), function(s) {
  m <- models[[paste0("polynomial_", s)]]
  cbind(sample = s, contrast(m, log(150)*unit(m, "log_size_midpoint") + log(150)^2*unit(m, "log_size_midpoint_sq")))
}))
write_csv(polynomial, "polynomial_101_contrasts")
all_coefs <- bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  bind_rows(lapply(names(m$b), function(term) cbind(model = name, term = term, contrast(m, unit(m, term)))))
}))
write_csv(all_coefs, "coefficients")
metadata <- bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  data.frame(model = name, n = m$n, r2 = m$r2, df = m$df, cluster = m$cluster, sample_hash = m$sample_hash, formula = m$rhs)
}))
write_csv(metadata, "models")

# Independently re-estimate a non-Solo normalization and test covariance as well as coefficients.
rebase_checks <- list()
for (name in c("common4", "simple", "geo_interacted4", "trend")) {
  original <- models[[name]]
  alternative_rhs <- gsub("ref = 'Solo'", "ref = '101+'", original$rhs, fixed = TRUE)
  m <- feols(as.formula(paste("log_ingreso_hora_real ~", alternative_rhs)), data = d,
    weights = ~fex, cluster = as.formula(original$cluster), lean = TRUE)
  for (sz in setdiff(sizes, "101+")) {
    old_term <- paste0("tamano_empresa::", sz, if (name == "trend") ":year_trend" else "")
    r <- est[est$model == name & est$reference == "101+" & est$size == sz & est$parameter %in% c("common", "informal"), ]
    rebase_checks[[length(rebase_checks)+1L]] <- data.frame(model = name, size = sz,
      coef_error = unname(coef(m)[old_term])-r$estimate,
      se_error = unname(sqrt(diag(vcov(m)))[old_term])-r$std.error)
  }
}
checks <- bind_rows(rebase_checks)
stopifnot(max(abs(as.matrix(checks[, c("coef_error", "se_error")]))) < 1e-7)
write_csv(checks, "reference_invariance_check")
reference <- read.csv(file.path(paper, "Paper/tables/regression_local_geography_formality_robustness.csv"))
validation <- bind_rows(lapply(seq_len(nrow(reference)), function(i) {
  row <- reference[i, ]
  model <- paste0("geo_interacted", gsub("[()]", "", row$model))
  r <- est[est$model == model & est$reference == row$reference_size & est$size == row$size, ]
  data.frame(model = model, reference = row$reference_size, size = row$size,
    informal_error = r$estimate[r$parameter == "informal"]-row$informal_estimate,
    formal_error = r$estimate[r$parameter == "formal"]-row$formal_estimate,
    informal_se_error = r$std.error[r$parameter == "informal"]-row$informal_se,
    formal_se_error = r$std.error[r$parameter == "formal"]-row$formal_se)
}))
write_csv(validation, "previous_table_comparison")
write_csv(checks[checks$model == "geo_interacted4", ], "preferred_replication_check")

# Optional historical-data check is read-only and never changes the canonical outputs.
if (length(args) >= 2) {
  old <- prepare(args[2])
  fit_model("historical_simple", paste(interacted_rhs, "| sector_year"), data = old)
  old_output <- read.csv(file.path(cjc, "Paper/tables/regression_formality_interaction_coefficients.csv"))
  hist <- models$historical_simple
  hist_rows <- bind_rows(lapply(sizes[-1], function(sz) {
    z <- profile(hist, sz)
    was <- old_output$estimate[old_output$tamano_empresa == sz & old_output$parameter == "beta"]
    data.frame(size = sz, archived_table = was, historical_refit = sum(z*hist$b),
      current_refit = sum(profile(models$simple, sz)*models$simple$b))
  }))
  stopifnot(max(abs(hist_rows$archived_table-hist_rows$historical_refit)) < 1e-7)
  hist_rows$historical_n <- hist$n
  hist_rows$current_n <- models$simple$n
  write_csv(hist_rows, "historical_data_check")
  if (nrow(old) == nrow(d) && identical(old$row_id, d$row_id)) {
    differences <- bind_rows(lapply(cols, function(col) {
      a <- old[[col]]; b <- d[[col]]
      if (is.factor(a)) a <- as.character(a)
      if (is.factor(b)) b <- as.character(b)
      changed <- xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
      data.frame(variable = col, differing_rows = sum(changed),
        max_absolute_difference = if (is.numeric(a)) max(abs(a-b), na.rm = TRUE) else NA_real_)
    }))
    write_csv(differences, "historical_variable_changes")
  }
  rm(old)
}
writeLines(c(paste("Input MD5:", unname(tools::md5sum(input))),
  paste("Occupation harmonization:", occupation_harmonization_version),
  paste("Input rows in common sample:", nrow(d)),
  "Inference: two-sided Student t with fixest cluster degrees of freedom for all contrasts.",
  trimws(capture.output(sessionInfo()), which = "right")), file.path(out, "provenance.txt"))
saveRDS(models, file.path(out, "aggregate_models.rds"))
message("Canonical regression outputs and validation checks complete.")
