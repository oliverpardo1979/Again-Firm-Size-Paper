# Exploratory comparisons only. This script never writes manuscript files.
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
cjc <- file.path(dirname(paper), "CJC-Monitor")
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(dplyr); library(fixest)})
source(file.path(paper, "replication/harmonize_occupation.R"))
setFixest_nthreads(4)
out <- file.path(paper, "replication/salaried_extensions_output")
cache <- file.path(paper, "build/salaried_extensions")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
old_models <- readRDS(file.path(paper, "replication/preferred_output/aggregate_models.rds"))
old_salary <- readRDS(file.path(paper, "replication/salaried_output/aggregate_models.rds"))$Salaried
income_cache <- readRDS(file.path(paper, "replication/output/private_cache/preferred_fit_and_2025.rds"))
sample_path <- file.path(paper, "build/regression_sample.rds")
message("Reading the existing regression sample")
d <- readRDS(sample_path)
signature <- attr(d, "cache_signature")
stopifnot(identical(signature[[3]], occupation_harmonization_version),
          identical(income_cache$signature$occupation, occupation_harmonization_version),
          signature[[1]] == income_cache$signature$size,
          signature[[2]] == income_cache$signature$mtime,
          all(d$wage_employee == (d$occupation_harmonized_code %in% c(1, 2, 3, 8))),
          !any(as.character(d$anio) == "2020"))
source_info <- file.info(file.path(paper, "data/GEIH_primary_income_2008_2025.dta"))
stopifnot(source_info$size == signature[[1]], as.numeric(source_info$mtime) == signature[[2]])
remove_singletons <- function(x) {
  n <- tabulate(as.integer(x$sector_depto_year), nbins = nlevels(x$sector_depto_year))
  x[n[as.integer(x$sector_depto_year)] > 1L, ]
}
d <- remove_singletons(d)
stopifnot(nrow(d) == 5426174L)
employee <- remove_singletons(d[d$wage_employee, ])
stopifnot(nrow(employee) == 2765713L)
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1L)
base <- paste0("i(tamano_empresa, ref = 'Solo') * formal + mujer + edad + edad2 + ",
               "i(educacion, ref = '", edu, "') + i(posicion_ocupacional_label)")
rhs <- paste(base, "| sector_depto_year")
cluster_names <- c("Sector-department", "Sector", "Department", "Two-way sector + department")

fit <- function(name, data, model_rhs = rhs, keep_target = FALSE) {
  path <- file.path(cache, paste0(name, ".rds"))
  key <- list(version = 1L, signature = signature, rhs = model_rhs, n = nrow(data),
              years = sort(unique(as.character(data$anio))), keep_target = keep_target)
  saved <- if (file.exists(path)) readRDS(path) else NULL
  if (!is.null(saved) && identical(saved$key, key)) {
    message("Reusing ", name)
    return(saved$model)
  }
  message(format(Sys.time()), " Estimating ", name, " on ", nrow(data), " observations")
  warnings <- character()
  m <- withCallingHandlers(feols(as.formula(paste("log_ingreso_hora_real ~", model_rhs)),
    data = data, weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)) })
  stopifnot(nobs(m) == nrow(data))
  G <- c(length(unique(data$sector_depto)), length(unique(data$sector)), length(unique(data$depto)))
  V <- list(vcov(m), vcov(m, cluster = ~sector), vcov(m, cluster = ~depto))
  # Match the manuscript audit's multiway covariance without an eigenvalue repair.
  V[[4]] <- (V[[2]] / (G[2]/(G[2]-1)) + V[[3]] / (G[3]/(G[3]-1)) -
               V[[1]] / (G[1]/(G[1]-1))) * min(G[2:3])/(min(G[2:3])-1)
  names(V) <- cluster_names
  df <- setNames(c(G-1, min(G[2:3])-1), cluster_names)
  ans <- list(b = coef(m), covariance = V, degrees = df, n = nobs(m),
              r2 = unname(fitstat(m, "r2")[[1]]), rhs = model_rhs, base = "Solo", warnings = warnings)
  if (keep_target) ans$target_eta <- fitted(m)[as.character(data$anio) == "2025"]
  saveRDS(list(key = key, model = ans), path)
  rm(m)
  gc()
  ans
}
wrap_old <- function(m) {
  m$base <- "Solo"
  m$covariance <- setNames(list(m$V, m$V_sector), cluster_names[1:2])
  m$degrees <- setNames(c(m$df, m$df_sector), cluster_names[1:2])
  m
}
unit <- function(m, candidates) {
  term <- intersect(candidates, names(m$b))
  stopifnot(length(term) == 1L)
  z <- setNames(numeric(length(m$b)), names(m$b))
  z[term] <- 1
  z
}
profile <- function(m, size, formal, post = FALSE) {
  z <- setNames(numeric(length(m$b)), names(m$b))
  if (size == m$base) return(z)
  term <- paste0("tamano_empresa::", size)
  z <- unit(m, term)
  if (formal) z <- z + unit(m, c(paste0(term, ":formal"), paste0("formal:", term)))
  if (post) {
    z <- z + unit(m, c(paste0(term, ":post"), paste0("post:", term)))
    if (formal) z <- z + unit(m, c(paste0(term, ":formal:post"), paste0("formal:", term, ":post"),
      paste0(term, ":post:formal"), paste0("post:", term, ":formal"), paste0("formal:post:", term), paste0("post:formal:", term)))
  }
  z
}
contrast <- function(m, z, clustering = "Sector-department") {
  b <- sum(z*m$b)
  variance <- drop(t(z) %*% m$covariance[[clustering]] %*% z)
  stopifnot(is.finite(variance), variance > 0)
  se <- sqrt(variance)
  df <- m$degrees[[clustering]]
  critical <- qt(.975, df)
  data.frame(estimate = b, std.error = se, p.value = 2*pt(abs(b/se), df, lower.tail = FALSE),
             premium = 100*expm1(b), ci_low = 100*expm1(b-critical*se),
             ci_high = 100*expm1(b+critical*se), df = df)
}
checks <- list()
check <- function(label, error, tolerance = 1e-7) {
  checks[[length(checks)+1L]] <<- data.frame(check = label, error = error, tolerance = tolerance)
  write_csv(bind_rows(checks), "replication_checks")
  stopifnot(is.finite(error), abs(error) < tolerance)
}

pooled <- fit("salaried_pooled", employee, keep_target = TRUE)
for (size in sizes[-1]) for (f in 0:1) {
  old_z <- profile(old_salary, size, f)-profile(old_salary, "Solo", f)
  z <- profile(pooled, size, f)
  check(paste("Existing salaried coefficient", size, f), sum(z*pooled$b)-sum(old_z*old_salary$b))
  check(paste("Existing salaried standard error", size, f),
        sqrt(drop(t(z)%*%pooled$covariance[[1]]%*%z))-sqrt(drop(t(old_z)%*%old_salary$V%*%old_z)))
}
annual <- list()
models <- list(salaried_pooled = pooled)
for (year in levels(d$anio)) {
  models[[paste0("salaried_year", year)]] <- fit(paste0("salaried_year", year), employee[employee$anio == year, ])
  for (sample in c("All", "Salaried")) {
    m <- if (sample == "All") wrap_old(old_models[[paste0("year", year)]]) else models[[paste0("salaried_year", year)]]
    for (ref in c("Solo", "11-19")) for (size in setdiff(sizes, ref)) for (f in 0:1) {
      annual[[length(annual)+1L]] <- cbind(sample = sample, year = as.integer(year), reference = ref,
        size = size, group = if (f) "Formal" else "Informal",
        contrast(m, profile(m, size, f)-profile(m, ref, f)))
    }
  }
  write_csv(bind_rows(annual), "annual_profiles")
}
endpoint_rows <- list()
formality_tests <- list()
for (sample in c("All", "Salaried")) {
  data <- if (sample == "All") d else employee
  data <- data[as.character(data$anio) %in% c("2008", "2025"), ]
  data$post <- as.integer(as.character(data$anio) == "2025")
  m <- fit(paste0(tolower(sample), "_endpoints"), data, paste0("(", base, ") * post | sector_depto_year"))
  models[[paste0(tolower(sample), "_endpoints")]] <- m
  if (sample == "All") {
    old <- old_models$endpoints
    check("Existing full-sample joint endpoint coefficients", max(abs(m$b-old$b[names(m$b)])))
    check("Existing full-sample endpoint covariance", max(abs(m$covariance[[1]]-old$V[names(m$b), names(m$b)])))
  }
  for (ref in c("Solo", "11-19")) for (size in setdiff(sizes, ref)) for (f in 0:1) {
    early <- profile(m, size, f)-profile(m, ref, f)
    late <- profile(m, size, f, TRUE)-profile(m, ref, f, TRUE)
    for (yr in c(2008, 2025)) {
      a <- sum((if (yr == 2008) early else late)*m$b)
      annual_m <- if (sample == "All") wrap_old(old_models[[paste0("year", yr)]]) else models[[paste0("salaried_year", yr)]]
      b <- sum((profile(annual_m, size, f)-profile(annual_m, ref, f))*annual_m$b)
      check(paste("Annual/joint endpoints", sample, yr, ref, size, f), a-b)
    }
    for (cl in cluster_names) {
      p0 <- 100*expm1(sum(early*m$b))
      p1 <- 100*expm1(sum(late*m$b))
      endpoint_rows[[length(endpoint_rows)+1L]] <- cbind(sample = sample, reference = ref, size = size,
        group = if (f) "Formal" else "Informal", clustering = cl, premium_2008 = p0, premium_2025 = p1,
        change_pp = p1-p0, contrast(m, late-early, cl))
    }
  }
  for (cl in cluster_names) for (period in c("2008", "2025", "Change")) {
    zi0 <- profile(m, "101+", 0)
    zf0 <- profile(m, "101+", 1)
    zi1 <- profile(m, "101+", 0, TRUE)
    zf1 <- profile(m, "101+", 1, TRUE)
    z <- switch(period, "2008" = zi0-zf0, "2025" = zi1-zf1, "Change" = (zi1-zi0)-(zf1-zf0))
    formality_tests[[length(formality_tests)+1L]] <- cbind(sample = sample, period = period,
      comparison = "Informal minus formal, 101+/solo", clustering = cl, contrast(m, z, cl))
  }
  write_csv(bind_rows(endpoint_rows), "endpoint_changes")
  write_csv(bind_rows(formality_tests), "dynamic_formality_tests")
}
rm(data)
gc()

# Predict incomes in each population using its own pooled coefficients and FE.
full_target <- income_cache$target
full_model <- wrap_old(old_models$preferred)
check("Full-sample income-cache coefficients", max(abs(income_cache$beta-full_model$b[names(income_cache$beta)])))
salary_cells <- unique(as.character(employee$sector_depto_year))
salary_target <- full_target[full_target$wage_employee & as.character(full_target$sector_depto_year) %in% salary_cells, ]
est_target <- employee[as.character(employee$anio) == "2025", ]
stopifnot(nrow(salary_target) == nrow(est_target), nrow(salary_target) == length(pooled$target_eta))
for (name in c("formal", "fex", "log_ingreso_hora_real", "occupation_harmonized_code", "tamano_empresa", "sector_depto_year"))
  stopifnot(identical(as.character(salary_target[[name]]), as.character(est_target[[name]])))
salary_full_prediction <- salary_target
salary_target$eta <- pooled$target_eta
stopifnot(all(full_target$horas > 0), all(is.finite(full_target$horas)))
sample_audit <- bind_rows(lapply(c("All", "Salaried"), function(sample) {
  x <- if (sample == "All") full_target else salary_target
  data.frame(sample = sample, pooled_observations = if (sample == "All") nrow(d) else nrow(employee),
    observations_2025 = nrow(x), workers_2025 = sum(x$fex), formal_workers_2025 = sum(x$fex[x$formal == 1]),
    informal_workers_2025 = sum(x$fex[x$formal == 0]),
    weighted_weekly_hours_2025 = weighted.mean(x$horas, x$fex))
}))
write_csv(sample_audit, "sample_audit")
scenarios_out <- list()
origin_out <- list()
support_out <- list()
profile_out <- list()
for (sample in c("All", "Salaried", "Salaried_full_coefficients")) {
  t <- switch(sample, All = full_target, Salaried = salary_target, Salaried_full_coefficients = salary_full_prediction)
  m <- if (sample == "Salaried") pooled else full_model
  grid <- expand.grid(size = sizes, formal = 0:1, stringsAsFactors = FALSE)
  Z <- do.call(rbind, lapply(seq_len(nrow(grid)), function(j) {
    z <- profile(m, grid$size[j], grid$formal[j])
    if (grid$formal[j]) z <- z + unit(m, "formal")
    z
  }))
  lp <- as.vector(Z%*%m$b)
  profile_out[[sample]] <- cbind(sample = sample, grid, log_profile = lp)
  origin <- match(as.character(t$tamano_empresa), sizes) + 9*t$formal
  scenarios <- list(formalize_same_size = ifelse(t$formal == 0, origin+9L, origin),
    formal_to_101 = ifelse(t$formal == 1, 18L, origin),
    informal_to_101 = ifelse(t$formal == 0, 9L, origin), combined_formal_101 = rep(18L, nrow(t)))
  key <- function(size, f) paste(t$sector, t$depto, t$posicion_ocupacional_label, size, f, sep = "|")
  observed_keys <- table(key(t$tamano_empresa, t$formal))
  for (scenario in names(scenarios)) {
    intended <- scenarios[[scenario]]
    moved <- intended != origin
    counts <- as.numeric(observed_keys[key(grid$size[intended], grid$formal[intended])])
    counts[is.na(counts)] <- 0
    support_out[[length(support_out)+1L]] <- data.frame(sample = sample, scenario = scenario,
      absent_destination_pct_of_movers = 100*sum(t$fex[moved & counts == 0])/sum(t$fex[moved]),
      fewer_than_30_pct_of_movers = 100*sum(t$fex[moved & counts < 30])/sum(t$fex[moved]))
    for (rule in c("unrestricted", "target_n30")) {
      dest <- if (rule == "unrestricted") intended else ifelse(counts >= 30, intended, origin)
      movers <- dest != origin
      delta <- lp[dest]-lp[origin]
      for (method in c("predicted", "observed_residual_preserved")) for (metric in c("weekly", "hourly")) {
        y <- if (method == "predicted") exp(t$eta) else t$ingreso_hora_real
        if (metric == "weekly") y <- y*t$horas
        mass <- t$fex*y
        for (population in c("all", "movers", "target_group")) {
          sel <- switch(population, all = rep(TRUE, nrow(t)), movers = movers,
            target_group = switch(scenario, formalize_same_size = t$formal == 0,
              informal_to_101 = t$formal == 0, formal_to_101 = t$formal == 1, rep(TRUE, nrow(t))))
          gain <- 100*sum(mass[sel]*expm1(delta[sel]))/sum(mass[sel])
          scenarios_out[[length(scenarios_out)+1L]] <- data.frame(sample = sample, scenario = scenario,
            support = rule, method = method, metric = metric, population = population,
            gain_pct = gain, workers_total = sum(t$fex), workers_moved = sum(t$fex[movers]),
            moved_worker_share_pct = 100*sum(t$fex[movers])/sum(t$fex),
            baseline_mover_income_share_pct = 100*sum(mass[movers])/sum(mass),
            workers_with_lower_predictions_pct_of_movers = 100*sum(t$fex[movers & delta < -1e-12])/sum(t$fex[movers]))
        }
        origin_out[[length(origin_out)+1L]] <- data.frame(origin = origin, dest = dest, mass = mass, weight = t$fex) %>%
          group_by(origin, dest) %>% summarise(baseline_mass = sum(mass), workers = sum(weight), .groups = "drop") %>%
          mutate(sample = sample, scenario = scenario, support = rule, method = method, metric = metric,
                 delta_log = lp[dest]-lp[origin])
      }
    }
  }
}
write_csv(bind_rows(scenarios_out), "income_scenarios")
write_csv(bind_rows(origin_out), "income_origin_aggregates")
write_csv(bind_rows(support_out), "income_support")
write_csv(bind_rows(profile_out), "pooled_income_profiles")
saveRDS(models, file.path(cache, "aggregate_models.rds"))
coefs <- bind_rows(lapply(names(models), function(name) data.frame(model = name, term = names(models[[name]]$b), estimate = models[[name]]$b)))
write_csv(coefs, "coefficients")
covariances <- bind_rows(lapply(c("all_endpoints", "salaried_endpoints"), function(name) {
  m <- models[[name]]
  bind_rows(lapply(names(m$covariance), function(cl) {
    z <- as.data.frame(as.table(m$covariance[[cl]]), stringsAsFactors = FALSE)
    names(z) <- c("term1", "term2", "covariance")
    cbind(model = name, clustering = cl, z)
  }))
}))
write_csv(covariances, "endpoint_covariances")
write_csv(bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  data.frame(model = name, n = m$n, r2 = m$r2, formula = m$rhs, warnings = paste(m$warnings, collapse = " | "))
})), "models")
writeLines(c(paste("Run:", Sys.time()), paste("Occupation recoding:", occupation_harmonization_version),
  "Salaried employees: private-sector, government, domestic, and day laborers, with formal and informal jobs retained.",
  "Same preferred specification, expansion weights, pooled years and singleton exclusions as the existing salaried exercise.",
  "Annual regressions let every slope vary across years. Joint endpoint model preserves within-cluster cross-year covariance.",
  "Endpoint p-values test changes in log premiums, not ratios of arithmetic mean wages.",
  "Income scenarios use each population's own pooled coefficients and fitted sector-department-year effects on its 2025 workers.",
  "Sector, department, occupational position, worker characteristics and hours stay fixed. No equilibrium response is modeled.",
  "Common retransformation factors cancel from gains. Income totals cover the indicated population, not always the entire workforce.",
  "Expansion factors are used as stored. The full target reproduces the manuscript's 22.6 million workers.",
  "Salaried_full_coefficients is a composition-only bridge, not the main salaried estimate.",
  "Source data and existing manuscript tables, figures, PDFs and replication outputs are unchanged.",
  trimws(capture.output(sessionInfo()), which = "right")), file.path(out, "provenance.txt"))
message("Completed exploratory salaried dynamics and income scenarios: ", out)
print(sample_audit)
print(bind_rows(endpoint_rows) %>% filter(reference == "Solo", size == "101+", clustering %in% cluster_names[1:2]) %>%
        select(sample, group, clustering, premium_2008, premium_2025, change_pp, p.value))
print(bind_rows(scenarios_out) %>% filter(sample != "Salaried_full_coefficients", support == "unrestricted",
        method == "predicted", metric == "weekly", population %in% c("all", "movers")) %>%
        select(sample, scenario, population, gain_pct, workers_moved))
