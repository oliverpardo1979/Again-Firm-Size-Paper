# Four fits on the adopted input. No baseline caches or manuscript writes.
Sys.setenv(OMP_NUM_THREADS = "2", OPENBLAS_NUM_THREADS = "2", MKL_NUM_THREADS = "2")
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 1L)
input <- normalizePath(if (length(args)) args[1] else
  file.path(paper, "data/GEIH_primary_income_2008_2025.dta"), winslash = "/", mustWork = TRUE)
out <- file.path(paper, "replication/period_sensitivity_output")
cache <- file.path(paper, "build/period_sensitivity")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
suppressPackageStartupMessages({library(haven); library(dplyr); library(fixest)})
source(file.path(paper, "replication/harmonize_occupation.R"))
setFixest_nthreads(2)
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8")
years <- c(2010:2019, 2021:2025)
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
clusters <- c("Sector-department", "Sector")
expected <- data.frame(sample = c("All", "Salaried"), complete = c(4839346L, 2476870L),
  estimation = c(4839217L, 2476733L), endpoints = c(653437L, 335655L), target = c(341056L, 185827L))
reference_files <- c("replication/primary_income_output/input_definition.json",
  "replication/primary_income_output/input_coverage.csv", "replication/preferred_output/models.csv",
  "replication/preferred_output/provenance.txt", "replication/salaried_output/contrasts.csv",
  "replication/salaried_extensions_output/models.csv", "replication/salaried_extensions_output/annual_profiles.csv",
  "replication/salaried_extensions_output/sample_audit.csv", "replication/salaried_extensions_output/income_scenarios.csv",
  "replication/salaried_extensions_output/endpoint_changes.csv")
reference_hashes <- unname(tools::md5sum(file.path(paper, reference_files)))
stopifnot(!anyNA(reference_hashes))
write_csv(data.frame(file = reference_files, md5 = reference_hashes), "baseline_manifest")
input_hash <- unname(tools::md5sum(input))
baseline_hash <- sub("Input MD5: ", "", readLines(file.path(paper,
  "replication/preferred_output/provenance.txt"), n = 1L))
stopifnot(identical(input_hash, baseline_hash))
signature <- list(version = 1L, input_md5 = input_hash, years = years,
  script_md5 = unname(tools::md5sum(script)),
  harmonization_md5 = unname(tools::md5sum(file.path(paper, "replication/harmonize_occupation.R"))),
  R = R.version.string, packages = sapply(c("haven", "dplyr", "fixest"), function(p) as.character(packageVersion(p))))
write_csv(data.frame(field = c("status", "input_md5", "input_bytes", "input_definition", "years",
  "threads", "script_md5", "harmonization_md5", "R"), value = c("running", input_hash,
  file.info(input)$size, "primary-income-2026-10-21", paste(years, collapse = ","), 2,
  signature$script_md5, signature$harmonization_md5, R.version.string)), "run_metadata")
writeLines(c(paste("Input:", input), paste("R_LIBS_USER:", Sys.getenv("R_LIBS_USER")),
  capture.output(sessionInfo())), file.path(cache, "local_environment.txt"))

message("Reading adopted input directly, MD5 ", input_hash)
cols <- c("anio", "MES", "depto", "edad", "sector", "tamano_empresa", "educacion",
  "posicion_ocupacional_label", "mujer", "formal", "fex", "horas", "log_ingreso_hora_real")
d <- read_dta(input, col_select = all_of(cols))
stopifnot(nrow(d) == 5426316L,
  identical(attr(d, "label"), "GEIH primary income 2026-10-21, aligned occupation codes"))
d <- harmonize_occupation(d)
d$row_id <- seq_len(nrow(d))
d <- d[as.integer(d$anio) %in% years, ]
d <- d %>% mutate(across(c(anio, depto, sector, educacion, posicion_ocupacional_label), factor),
  edad = as.numeric(edad), edad2 = edad^2, tamano_empresa = factor(tamano_empresa, levels = sizes),
  sector_depto = interaction(sector, depto, drop = TRUE),
  sector_depto_year = interaction(sector, depto, anio, drop = TRUE))
stopifnot(nrow(d) == expected$complete[1], sum(d$wage_employee) == expected$complete[2],
  !anyNA(d[cols]), all(is.finite(d$log_ingreso_hora_real)), all(d$fex > 0),
  all(d$horas > 0 & d$horas <= 168), all(d$formal %in% 0:1),
  all(d$wage_employee == (d$occupation_harmonized_code %in% c(1, 2, 3, 8))))
coverage <- read.csv(file.path(paper, "replication/primary_income_output/input_coverage.csv"))
annual <- read.csv(file.path(paper, "replication/salaried_extensions_output/annual_profiles.csv"))
annual <- annual[annual$reference == "Solo" & annual$year %in% years, ]
stopifnot(nrow(annual) == 480L)
write_csv(annual, "annual_profiles_reused")
old_full_models <- read.csv(file.path(paper, "replication/preferred_output/models.csv"))
old_salary_models <- read.csv(file.path(paper, "replication/salaried_extensions_output/models.csv"))
old_target <- read.csv(file.path(paper, "replication/salaried_extensions_output/sample_audit.csv"))
checks <- list()
check <- function(name, error, tolerance = 1e-7) {
  stopifnot(length(error) == 1L, is.finite(error), abs(error) < tolerance)
  checks[[length(checks)+1L]] <<- data.frame(check = name, error = error, tolerance = tolerance)
}
remove_singletons <- function(x) {
  n <- tabulate(as.integer(x$sector_depto_year), nbins = nlevels(x$sector_depto_year))
  x[n[as.integer(x$sector_depto_year)] > 1L, ]
}
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1L)
base <- paste0("i(tamano_empresa, ref = 'Solo') * formal + mujer + edad + edad2 + ",
  "i(educacion, ref = '", edu, "') + i(posicion_ocupacional_label)")
rhs <- paste(base, "| sector_depto_year")
fit <- function(name, data, model_rhs, keep_target = FALSE) {
  key <- list(signature = signature, model = name, formula = model_rhs, n = nrow(data),
    keep_target = keep_target, clusters = clusters)
  path <- file.path(cache, paste0(name, ".rds"))
  saved <- if (file.exists(path)) readRDS(path) else NULL
  if (!is.null(saved) && identical(saved$key, key)) {
    message("Reusing isolated sensitivity fit ", name)
    return(saved$model)
  }
  message(format(Sys.time()), " Estimating ", name, " on ", nrow(data), " observations with two threads")
  warnings <- character()
  m <- withCallingHandlers(feols(as.formula(paste("log_ingreso_hora_real ~", model_rhs)),
    data = data, weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)) })
  stopifnot(nobs(m) == nrow(data))
  ans <- list(b = coef(m), covariance = setNames(list(vcov(m), vcov(m, cluster = ~sector)), clusters),
    degrees = setNames(c(degrees_freedom(m, "t"), degrees_freedom(m, "t", vcov = ~sector)), clusters),
    n = nobs(m), r2 = unname(fitstat(m, "r2")[[1]]), formula = model_rhs, warnings = warnings,
    groups = setNames(c(length(unique(data$sector_depto)), length(unique(data$sector))), clusters))
  if (keep_target) ans$target_eta <- fitted(m)[as.character(data$anio) == "2025"]
  saveRDS(list(key = key, model = ans), path)
  rm(m)
  gc()
  ans
}
unit <- function(m, candidates) {
  term <- intersect(candidates, names(m$b))
  stopifnot(length(term) == 1L)
  z <- setNames(numeric(length(m$b)), names(m$b))
  z[term] <- 1
  z
}
profile <- function(m, size, formal, post = FALSE) {
  if (size == "Solo") return(setNames(numeric(length(m$b)), names(m$b)))
  term <- paste0("tamano_empresa::", size)
  z <- unit(m, term)
  if (formal) z <- z + unit(m, c(paste0(term, ":formal"), paste0("formal:", term)))
  if (post) {
    z <- z + unit(m, c(paste0(term, ":post"), paste0("post:", term)))
    if (formal) z <- z + unit(m, c(paste0(term, ":formal:post"), paste0("formal:", term, ":post"),
      paste0(term, ":post:formal"), paste0("post:", term, ":formal"), paste0("formal:post:", term),
      paste0("post:formal:", term)))
  }
  z
}
contrast <- function(m, z, cl) {
  b <- sum(z*m$b)
  variance <- drop(t(z) %*% m$covariance[[cl]] %*% z)
  stopifnot(is.finite(variance), variance > 0)
  se <- sqrt(variance)
  df <- m$degrees[[cl]]
  critical <- qt(.975, df)
  data.frame(estimate = b, std.error = se, p.value = 2*pt(abs(b/se), df, lower.tail = FALSE),
    conf.low = b-critical*se, conf.high = b+critical*se,
    premium = 100*expm1(b), ci_low = 100*expm1(b-critical*se), ci_high = 100*expm1(b+critical*se), df = df)
}
models <- targets <- sample_rows <- monthly_rows <- profile_rows <- gap_rows <- endpoint_rows <- endpoint_levels <- list()
for (sample in expected$sample) {
  j <- match(sample, expected$sample)
  x <- if (sample == "All") d else d[d$wage_employee, ]
  before <- nrow(x)
  for (year in years) check(paste("Complete observations", sample, year),
    sum(as.character(x$anio) == year) - coverage[coverage$year == year, if (sample == "All") "n" else "salaried_n"])
  x <- remove_singletons(x)
  stopifnot(nrow(x) == expected$estimation[j])
  month_counts <- x %>% group_by(anio, MES) %>% summarise(n = n(), workers = sum(fex), .groups = "drop")
  stopifnot(nrow(month_counts) == 180L, all(month_counts$n > 0))
  monthly_rows[[sample]] <- mutate(month_counts, sample = sample)
  for (year in years) {
    old <- if (sample == "All") old_full_models else old_salary_models
    name <- paste0(if (sample == "All") "year" else "salaried_year", year)
    check(paste("Retained annual sample", sample, year), sum(as.character(x$anio) == year)-old$n[old$model == name])
  }
  name <- paste0(tolower(sample), "_pooled")
  m <- fit(name, x, rhs, TRUE)
  models[[name]] <- m
  target <- x[as.character(x$anio) == "2025", ]
  stopifnot(nrow(target) == expected$target[j], length(m$target_eta) == nrow(target))
  target$eta <- m$target_eta
  targets[[sample]] <- target
  sample_rows[[sample]] <- data.frame(sample = sample, complete_observations = before,
    pooled_observations = nrow(x), singletons_removed = before-nrow(x), observations_2025 = nrow(target),
    workers_2025 = sum(target$fex), formal_workers_2025 = sum(target$fex[target$formal == 1]),
    informal_workers_2025 = sum(target$fex[target$formal == 0]),
    weighted_weekly_hours_2025 = weighted.mean(target$horas, target$fex))
  for (field in c("observations_2025", "workers_2025", "formal_workers_2025", "informal_workers_2025",
    "weighted_weekly_hours_2025")) check(paste("Unchanged 2025 population", sample, field),
      sample_rows[[sample]][[field]]-old_target[old_target$sample == sample, field], 1e-6)
  for (cl in clusters) {
    for (size in sizes[-1]) for (f in 0:1) profile_rows[[length(profile_rows)+1L]] <-
      cbind(sample = sample, reference = "Solo", size = size, group = if (f) "Formal" else "Informal",
        clustering = cl, contrast(m, profile(m, size, f), cl))
    for (size in sizes) gap_rows[[length(gap_rows)+1L]] <- cbind(sample = sample, size = size,
      clustering = cl, contrast(m, unit(m, "formal") + profile(m, size, 1)-profile(m, size, 0), cl))
  }
  ep <- x[as.character(x$anio) %in% c("2010", "2025"), ]
  ep$post <- as.integer(as.character(ep$anio) == "2025")
  stopifnot(nrow(ep) == expected$endpoints[j])
  name <- paste0(tolower(sample), "_endpoints")
  m <- fit(name, ep, paste0("(", base, ") * post | sector_depto_year"))
  models[[name]] <- m
  for (size in sizes[-1]) for (f in 0:1) {
    group <- if (f) "Formal" else "Informal"
    early <- profile(m, size, f)
    late <- profile(m, size, f, TRUE)
    for (year in c(2010, 2025)) {
      z <- if (year == 2010) early else late
      old <- annual[annual$sample == sample & annual$year == year & annual$size == size & annual$group == group, ]
      check(paste("Annual/joint endpoint coefficient", sample, year, size, group), sum(z*m$b)-old$estimate)
      for (cl in clusters) endpoint_levels[[length(endpoint_levels)+1L]] <- cbind(sample = sample,
        year = year, reference = "Solo", size = size, group = group, clustering = cl, contrast(m, z, cl))
    }
    for (cl in clusters) endpoint_rows[[length(endpoint_rows)+1L]] <- cbind(sample = sample,
      reference = "Solo", size = size, group = group, clustering = cl,
      premium_2010 = 100*expm1(sum(early*m$b)), premium_2025 = 100*expm1(sum(late*m$b)),
      change_pp = 100*(exp(sum(late*m$b))-exp(sum(early*m$b))), contrast(m, late-early, cl))
  }
  write_csv(bind_rows(sample_rows), "sample_audit")
  write_csv(bind_rows(monthly_rows), "monthly_sample_counts")
  write_csv(bind_rows(profile_rows), "pooled_profiles")
  write_csv(bind_rows(gap_rows), "formal_informal_gaps")
  write_csv(bind_rows(endpoint_rows), "endpoint_changes")
  write_csv(bind_rows(endpoint_levels), "endpoint_levels")
  rm(x, ep, target, m)
  gc()
}
rm(d)
gc()

# Separate the coefficient change from the composition-only salaried comparison.
ix <- match(targets$Salaried$row_id, targets$All$row_id)
stopifnot(!anyNA(ix))
targets$Salaried_full_coefficients <- targets$Salaried
targets$Salaried_full_coefficients$eta <- targets$All$eta[ix]
scenario_rows <- origin_rows <- income_profiles <- list()
for (sample in names(targets)) {
  target <- targets[[sample]]
  m <- models[[if (sample == "Salaried") "salaried_pooled" else "all_pooled"]]
  grid <- expand.grid(size = sizes, formal = 0:1, stringsAsFactors = FALSE)
  lp <- vapply(seq_len(nrow(grid)), function(j) {
    z <- profile(m, grid$size[j], grid$formal[j])
    if (grid$formal[j]) z <- z + unit(m, "formal")
    sum(z*m$b)
  }, numeric(1))
  income_profiles[[sample]] <- cbind(sample = sample, grid, profile = seq_len(nrow(grid)), log_profile = lp)
  origin <- match(as.character(target$tamano_empresa), sizes)+9L*target$formal
  scenarios <- list(formalize_same_size = ifelse(target$formal == 0, origin+9L, origin),
    formal_to_101 = ifelse(target$formal == 1, 18L, origin),
    informal_to_101 = ifelse(target$formal == 0, 9L, origin), combined_formal_101 = rep(18L, nrow(target)))
  mass <- target$fex * target$horas * exp(target$eta)
  stopifnot(all(is.finite(mass)), all(mass > 0))
  for (scenario in names(scenarios)) {
    dest <- scenarios[[scenario]]
    moved <- dest != origin
    delta <- lp[dest]-lp[origin]
    check(paste("Nonmovers unchanged", sample, scenario), max(c(0, abs(delta[!moved]))))
    aggregated <- data.frame(origin = origin, dest = dest, mass = mass, weight = target$fex) %>%
      group_by(origin, dest) %>% summarise(baseline_mass = sum(mass), workers = sum(weight),
        observations = n(), .groups = "drop") %>% mutate(sample = sample, scenario = scenario,
          delta_log = lp[dest]-lp[origin])
    origin_rows[[length(origin_rows)+1L]] <- aggregated
    for (population in c("all", "movers", "target_group")) {
      select_population <- function(orig, destination) switch(population,
        all = rep(TRUE, length(orig)), movers = orig != destination,
        target_group = switch(scenario, formalize_same_size = orig <= 9L,
          informal_to_101 = orig <= 9L, formal_to_101 = orig > 9L, rep(TRUE, length(orig))))
      sel <- select_population(origin, dest)
      a <- aggregated[select_population(aggregated$origin, aggregated$dest), ]
      denominator <- sum(mass[sel])
      gain <- 100*sum(mass[sel]*expm1(delta[sel]))/denominator
      check(paste("Individual/aggregate income ratio", sample, scenario, population),
        gain-100*sum(a$baseline_mass*expm1(a$delta_log))/sum(a$baseline_mass), 1e-9)
      scenario_rows[[length(scenario_rows)+1L]] <- data.frame(sample = sample, scenario = scenario,
        support = "unrestricted", method = "predicted", metric = "weekly", population = population,
        gain_pct = gain, workers_total = sum(target$fex), workers_moved = sum(target$fex[moved]),
        denominator_workers = sum(target$fex[sel]), baseline_mass = denominator,
        counterfactual_mass = sum(mass[sel]*exp(delta[sel])),
        baseline_mean = denominator/sum(target$fex[sel]),
        counterfactual_mean = sum(mass[sel]*exp(delta[sel]))/sum(target$fex[sel]),
        moved_worker_share_pct = 100*sum(target$fex[moved])/sum(target$fex),
        baseline_mover_income_share_pct = 100*sum(mass[moved])/sum(mass),
        workers_with_lower_predictions_pct_of_movers = 100*sum(target$fex[moved & delta < -1e-12])/sum(target$fex[moved]))
    }
  }
}
write_csv(bind_rows(scenario_rows), "income_scenarios")
write_csv(bind_rows(origin_rows), "income_origin_aggregates")
write_csv(bind_rows(income_profiles), "pooled_income_profiles")
write_csv(bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  data.frame(model = name, n = m$n, r2 = m$r2, df = m$degrees[[1]], df_sector = m$degrees[[2]],
    clusters = m$groups[[1]], sector_clusters = m$groups[[2]], formula = m$formula,
    warnings = paste(m$warnings, collapse = " | "))
})), "models")
write_csv(bind_rows(lapply(names(models), function(name) data.frame(model = name,
  term = names(models[[name]]$b), estimate = models[[name]]$b))), "coefficients")
write_csv(bind_rows(lapply(names(models), function(name) bind_rows(lapply(clusters, function(cl) {
  v <- as.data.frame(as.table(models[[name]]$covariance[[cl]]), stringsAsFactors = FALSE)
  names(v) <- c("term1", "term2", "covariance")
  cbind(model = name, clustering = cl, v)
})))), "covariances")
check("Baseline reference files unchanged", sum(reference_hashes !=
  unname(tools::md5sum(file.path(paper, reference_files)))))
write_csv(bind_rows(checks), "replication_checks")
packages <- sort(loadedNamespaces())
write_csv(data.frame(package = packages,
  version = vapply(packages, function(p) as.character(packageVersion(p)), character(1)),
  built = vapply(packages, function(p) { b <- packageDescription(p)$Built; if (is.null(b)) "" else b }, character(1))),
  "package_versions")
writeLines(c(R.version.string, capture.output(sessionInfo()),
  "Adopted processed input only. This run is not a fresh replication from raw archives.",
  "2010-2019 and 2021-2025. Four fits. Two threads. No bootstrap or new model families.",
  "Annual profiles are reused after annual sample checks. Endpoint standard errors come from the joint fit.",
  "2025 scenarios use each sample's own pooled fitted effects and coefficients, with observed hours and weights fixed.",
  "Salaried_full_coefficients is a composition comparison, not the salaried estimate.",
  "Income levels omit a common retransformation factor, which cancels from all reported gains.",
  "2008-based outputs and manuscript sources are not modified."), file.path(out, "provenance.txt"))
metadata <- read.csv(file.path(out, "run_metadata.csv"))
metadata$value[metadata$field == "status"] <- "complete"
write_csv(metadata, "run_metadata")
message("Completed four-fit period sensitivity. Run validate_period_sensitivity.py next.")
