args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
cjc <- file.path(dirname(paper), "CJC-Monitor")
input <- if (length(args)) args[1] else file.path(cjc, "Datos/Processed/Paper-GEIH_base_modelo_personas_2008_2025.dta")
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr); library(fixest)})
setFixest_nthreads(4)
out <- file.path(paper, "replication/preferred_output")
cache <- file.path(paper, "build/preferred_extensions")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
signature <- c(file.info(input)$size, as.numeric(file.info(input)$mtime))
sample_path <- file.path(paper, "build/regression_sample.rds")
d <- if (file.exists(sample_path)) readRDS(sample_path) else NULL
if (is.null(d) || !identical(attr(d, "cache_signature"), signature)) {
  cols <- c("anio", "depto", "edad", "sector", "tamano_empresa", "educacion", "posicion_ocupacional_label", "mujer", "formal", "fex", "log_ingreso_hora_real")
  d <- read_dta(input, col_select = all_of(cols)) %>%
    mutate(row_id = row_number(), across(c(anio, depto, sector, educacion, posicion_ocupacional_label), factor),
      edad = as.numeric(edad), edad2 = edad^2, tamano_empresa = factor(tamano_empresa, levels = sizes)) %>%
    filter(is.finite(log_ingreso_hora_real), !is.na(tamano_empresa), !is.na(mujer), is.finite(edad),
      !is.na(educacion), !is.na(formal), !is.na(sector), !is.na(anio), is.finite(fex), fex > 0) %>%
    mutate(sector_year = interaction(sector, anio, drop = TRUE), sector_depto = interaction(sector, depto, drop = TRUE),
      sector_depto_year = interaction(sector, depto, anio, drop = TRUE),
      log_size_midpoint = log(c(1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, 150)[as.integer(tamano_empresa)]))
}
stopifnot(!anyNA(d$depto), !anyNA(d$posicion_ocupacional_label), !any(as.character(d$anio) == "2020"))
# Hold the preferred estimation sample fixed when comparing controls and clustering.
cell_n <- tabulate(as.integer(d$sector_depto_year), nbins = nlevels(d$sector_depto_year))
d <- d[cell_n[as.integer(d$sector_depto_year)] > 1L, ]
stopifnot(nrow(d) == 5268375L)
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1)
controls <- paste0("mujer + edad + edad2 + i(educacion, ref = '", edu, "')")
base <- paste("i(tamano_empresa, ref = 'Solo') * formal +", controls)
preferred_rhs <- paste(base, "+ i(posicion_ocupacional_label) | sector_depto_year")
models <- list()
fit_model <- function(name, rhs, data = d) {
  path <- file.path(cache, paste0(name, ".rds"))
  key <- list(version = 1L, signature = signature, rhs = rhs, n = nrow(data), years = sort(unique(as.character(data$anio))))
  saved <- if (file.exists(path)) readRDS(path) else NULL
  if (!is.null(saved) && identical(saved$key, key)) {
    message("Reusing ", name)
    ans <- saved$model
  } else {
    message("Estimating ", name, " on ", nrow(data), " observations")
    m <- feols(as.formula(paste("log_ingreso_hora_real ~", rhs)), data = data,
      weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE)
    sector_v <- vcov(m, cluster = ~sector)
    ans <- list(b = coef(m), V = vcov(m), V_sector = sector_v,
      df = degrees_freedom(m, "t"), df_sector = degrees_freedom(m, "t", vcov = ~sector),
      n = nobs(m), r2 = unname(fitstat(m, "r2")[[1]]), rhs = rhs)
    saveRDS(list(key = key, model = ans), path)
    rm(m)
    gc()
  }
  models[[name]] <<- ans
  invisible(ans)
}
unit <- function(m, candidates) {
  term <- intersect(candidates, names(m$b))
  stopifnot(length(term) == 1L)
  z <- setNames(numeric(length(m$b)), names(m$b))
  z[term] <- 1
  z
}
profile <- function(m, size, formal = 0, post = FALSE) {
  z <- setNames(numeric(length(m$b)), names(m$b))
  if (size == "Solo") return(z)
  term <- paste0("tamano_empresa::", size)
  z <- unit(m, term)
  if (formal == 1) z <- z + unit(m, c(paste0(term, ":formal"), paste0("formal:", term)))
  if (post) {
    z <- z + unit(m, c(paste0(term, ":post"), paste0("post:", term)))
    if (formal == 1) z <- z + unit(m, c(paste0(term, ":formal:post"), paste0("formal:", term, ":post"),
      paste0(term, ":post:formal"), paste0("post:", term, ":formal"), paste0("formal:post:", term), paste0("post:formal:", term)))
  }
  z
}
contrast <- function(m, z, sector = FALSE) {
  V <- if (sector) m$V_sector else m$V
  df <- if (sector) m$df_sector else m$df
  b <- sum(z*m$b)
  se <- sqrt(drop(t(z) %*% V %*% z))
  p <- 2*pt(abs(b/se), df, lower.tail = FALSE)
  critical <- qt(.975, df)
  data.frame(estimate = b, std.error = se, p.value = p, conf.low = b-critical*se,
    conf.high = b+critical*se, premium = 100*expm1(b), ci_low = 100*expm1(b-critical*se),
    ci_high = 100*expm1(b+critical*se), df = df)
}
fit_model("sector_year", paste(base, "| sector_year"))
fit_model("sector_dept_year", paste(base, "| sector_depto_year"))
fit_model("preferred", preferred_rhs)
reference <- readRDS(file.path(paper, "replication/regression_output/aggregate_models.rds"))$geo_interacted4
stopifnot(identical(names(reference$b), names(models$preferred$b)),
  max(abs(reference$b-models$preferred$b)) < 1e-7, max(abs(reference$V-models$preferred$V)) < 1e-7)
rows <- list()
for (ref in c("Solo", "101+", "11-19")) for (size in setdiff(sizes, ref)) for (f in 0:1) {
  m <- models$preferred
  rows[[length(rows)+1L]] <- cbind(reference = ref, size = size, group = if (f) "Formal" else "Informal",
    contrast(m, profile(m, size, f)-profile(m, ref, f)))
}
write_csv(bind_rows(rows), "profiles")
gaps <- bind_rows(lapply(sizes, function(size) cbind(size = size,
  contrast(models$preferred, unit(models$preferred, "formal") + profile(models$preferred, size, 1)-profile(models$preferred, size, 0)))))
write_csv(gaps, "formal_informal_gaps")
sens <- list()
for (name in c("sector_year", "sector_dept_year", "preferred")) for (f in 0:1) for (sector in c(FALSE, TRUE)) {
  sens[[length(sens)+1L]] <- cbind(model = name, group = if (f) "Formal" else "Informal",
    clustering = if (sector) "Sector" else "Sector-department", contrast(models[[name]], profile(models[[name]], "101+", f), sector))
}
write_csv(bind_rows(sens), "clustering_sensitivity")

# Year-by-year estimation is the fully year-interacted extension of all slopes.
annual <- list()
for (year in levels(d$anio)) {
  m <- fit_model(paste0("year", year), preferred_rhs, data = d[d$anio == year, ])
  for (size in sizes[-1]) for (f in 0:1) annual[[length(annual)+1L]] <-
    cbind(year = as.integer(year), size = size, group = if (f) "Formal" else "Informal", contrast(m, profile(m, size, f)))
  write_csv(bind_rows(annual), "annual_profiles")
}
# Joint endpoints retain cross-year covariance within the same cluster.
endpoint_data <- d[as.character(d$anio) %in% c("2008", "2025"), ]
endpoint_data$post <- as.integer(as.character(endpoint_data$anio) == "2025")
m <- fit_model("endpoints", paste0("(", base, " + i(posicion_ocupacional_label)) * post | sector_depto_year"), data = endpoint_data)
checks <- list()
changes <- list()
for (size in sizes[-1]) for (f in 0:1) {
  early <- profile(m, size, f)
  late <- profile(m, size, f, TRUE)
  for (yr in c(2008, 2025)) {
    a <- sum((if (yr == 2008) early else late)*m$b)
    annual_m <- models[[paste0("year", yr)]]
    b <- sum(profile(annual_m, size, f)*annual_m$b)
    checks[[length(checks)+1L]] <- data.frame(year = yr, size = size, group = if (f) "Formal" else "Informal", error = a-b)
  }
  changes[[length(changes)+1L]] <- cbind(size = size, group = if (f) "Formal" else "Informal",
    premium_2008 = 100*expm1(sum(early*m$b)), premium_2025 = 100*expm1(sum(late*m$b)), contrast(m, late-early))
}
endpoint_checks <- bind_rows(checks)
stopifnot(max(abs(endpoint_checks$error)) < 1e-7)
write_csv(endpoint_checks, "endpoint_replication_check")
write_csv(bind_rows(changes), "endpoint_changes")
rm(endpoint_data)
gc()

fit_model("elasticity_raw", "log_size_midpoint")
fit_model("elasticity_common", paste("log_size_midpoint + formal +", controls, "+ i(posicion_ocupacional_label) | sector_depto_year"))
fit_model("elasticity_interacted", paste("log_size_midpoint * formal +", controls, "+ i(posicion_ocupacional_label) | sector_depto_year"))
elasticities <- list()
for (sample in c("raw", "common", "Informal", "Formal", "Formal-minus-informal")) {
  name <- if (sample %in% c("raw", "common")) paste0("elasticity_", sample) else "elasticity_interacted"
  m <- models[[name]]
  z <- unit(m, "log_size_midpoint")
  if (sample == "Formal") z <- z + unit(m, c("log_size_midpoint:formal", "formal:log_size_midpoint"))
  if (sample == "Formal-minus-informal") z <- unit(m, c("log_size_midpoint:formal", "formal:log_size_midpoint"))
  elasticities[[length(elasticities)+1L]] <- cbind(sample = sample, contrast(m, z))
}
write_csv(bind_rows(elasticities), "elasticities")
extension_sensitivity <- list()
for (f in 0:1) for (sector in c(FALSE, TRUE)) {
  m <- models$endpoints
  z <- profile(m, "101+", f, TRUE)-profile(m, "101+", f)
  extension_sensitivity[[length(extension_sensitivity)+1L]] <- cbind(exercise = "Endpoint change, 101+/solo",
    group = if (f) "Formal" else "Informal", clustering = if (sector) "Sector" else "Sector-department", contrast(m, z, sector))
  m <- models$elasticity_interacted
  z <- unit(m, "log_size_midpoint")
  if (f) z <- z + unit(m, c("log_size_midpoint:formal", "formal:log_size_midpoint"))
  extension_sensitivity[[length(extension_sensitivity)+1L]] <- cbind(exercise = "Elasticity",
    group = if (f) "Formal" else "Informal", clustering = if (sector) "Sector" else "Sector-department", contrast(m, z, sector))
}
write_csv(bind_rows(extension_sensitivity), "extension_clustering_sensitivity")
for (name in c("preferred", "endpoints", "elasticity_interacted")) {
  m <- models[[name]]
  covariances <- bind_rows(lapply(c("Sector-department", "Sector"), function(clustering) {
    x <- as.data.frame(as.table(if (clustering == "Sector") m$V_sector else m$V), stringsAsFactors = FALSE)
    names(x) <- c("term1", "term2", "covariance")
    cbind(clustering = clustering, x)
  }))
  write_csv(covariances, paste0("covariance_", name))
}
write_csv(bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  data.frame(model = name, n = m$n, r2 = m$r2, df = m$df, df_sector = m$df_sector, formula = m$rhs)
})), "models")
write_csv(bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  bind_rows(lapply(names(m$b), function(term) cbind(model = name, term = term, contrast(m, unit(m, term)))))
})), "coefficients")
saveRDS(models, file.path(out, "aggregate_models.rds"))
writeLines(c(paste("Input MD5:", unname(tools::md5sum(input))),
  "All models use the preferred sample, GEIH weights, and two-sided cluster-t inference.",
  "Annual models allow all slopes to vary by year. Endpoint changes use a joint fully interacted model.",
  "Elasticities by formality are linear contrasts of one interacted model, not separate regressions.",
  "Aggregate caches contain only coefficients and covariance matrices. No microdata are published.",
  trimws(capture.output(sessionInfo()), which = "right")), file.path(out, "provenance.txt"))
message("Preferred extensions completed and preferred coefficients verified unchanged.")
