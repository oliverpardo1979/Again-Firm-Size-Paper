args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") {
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
}
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
stopifnot(length(script_arg) == 1)
paper <- dirname(dirname(normalizePath(sub("^--file=", "", script_arg), winslash = "/")))
source(file.path(paper, "replication/harmonize_occupation.R"))
root <- file.path(dirname(paper), "CJC-Monitor")
data_path <- normalizePath(if (length(args)) args[1] else
  file.path(paper, "data/GEIH_primary_income_2008_2025.dta"),
  winslash = "/", mustWork = TRUE)
out <- if (length(args) >= 2) args[2] else file.path(paper, "replication/output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, winslash = "/")
cache <- file.path(out, "private_cache")
dir.create(cache, showWarnings = FALSE)
.libPaths(c(file.path(root, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(fixest)
})
setFixest_nthreads(4)
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
write_table <- function(x, name) write.csv(x, file.path(out, name), row.names = FALSE, fileEncoding = "UTF-8")
message("Input: ", data_path)
data_info <- file.info(data_path)
signature <- list(size = data_info$size, mtime = as.numeric(data_info$mtime), occupation = occupation_harmonization_version,
                  reference = unname(tools::md5sum(file.path(paper, "Paper/tables/regression_local_geography_formality_robustness.csv"))))
cache_path <- file.path(cache, "preferred_fit_and_2025.rds")
saved <- if (file.exists(cache_path)) readRDS(cache_path) else NULL

if (is.null(saved) || !identical(saved$signature, signature)) {
  cols <- c("anio", "depto", "edad", "sector", "tamano_empresa", "educacion",
            "posicion_ocupacional_label", "mujer", "formal", "fex", "horas",
            "ingreso_hora_real", "log_ingreso_hora_real", "pensionado_ocupado")
  d <- harmonize_occupation(read_dta(data_path, col_select = all_of(cols)))
  raw_n <- nrow(d)
  message("Read ", raw_n, " rows")
  d <- d %>% mutate(
    anio = factor(anio), depto = factor(depto), sector = factor(sector),
    edad = as.numeric(edad), edad2 = edad^2,
    tamano_empresa = factor(tamano_empresa, levels = sizes),
    educacion = factor(educacion), posicion_ocupacional_label = factor(posicion_ocupacional_label),
    sector_depto = interaction(sector, depto, drop = TRUE),
    sector_depto_year = interaction(sector, depto, anio, drop = TRUE)
  ) %>% filter(
    is.finite(log_ingreso_hora_real), !is.na(tamano_empresa), !is.na(mujer),
    is.finite(edad), !is.na(educacion), !is.na(formal), !is.na(sector), !is.na(depto),
    !is.na(anio), is.finite(fex), fex > 0, !is.na(posicion_ocupacional_label)
  )
  stopifnot(!any(as.character(d$anio) == "2020"), all(d$formal %in% 0:1))
  education_ref <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
  stopifnot(length(education_ref) == 1)
  fml <- as.formula(paste0(
    "log_ingreso_hora_real ~ i(tamano_empresa, ref = 'Solo') * formal + ",
    "mujer + edad + edad2 + i(educacion, ref = '", education_ref,
    "') + i(posicion_ocupacional_label) | sector_depto_year"))
  message("Estimating preferred pooled specification on ", nrow(d), " candidate rows")
  fit <- feols(fml, data = d, weights = ~fex, cluster = ~sector_depto)
  message("Estimation complete: ", nobs(fit), " observations")
  used <- obs(fit)
  d <- d[used, ]
  stopifnot(nrow(d) == nobs(fit), nobs(fit) == 5426174L)
  d$eta <- fitted(fit)
  d$log_residual <- residuals(fit)
  pooled_cells <- d %>% group_by(sector, depto, posicion_ocupacional_label, tamano_empresa, formal) %>%
    summarise(n = n(), sum_w = sum(fex), neff = sum(fex)^2 / sum(fex^2), .groups = "drop")
  target <- d %>% filter(as.character(anio) == "2025")
  saved <- list(signature = signature, beta = coef(fit), V = vcov(fit),
                target = target, pooled_cells = pooled_cells, formula = deparse(fml),
                raw_n = raw_n, nobs = nobs(fit), r2 = as.numeric(fitstat(fit, "r2")),
                n_clusters = length(unique(d$sector_depto)),
                years = levels(d$anio), df_t = degrees_freedom(fit, "t"),
                session = capture.output(sessionInfo()))
  saveRDS(saved, cache_path, compress = FALSE)
  rm(d, fit)
  gc()
} else message("Reusing validated local estimation cache")

beta <- saved$beta
V <- saved$V
profiles <- expand.grid(size = sizes, formal = 0:1, stringsAsFactors = FALSE)
Z <- matrix(0, nrow(profiles), length(beta), dimnames = list(NULL, names(beta)))
for (j in seq_len(nrow(profiles))) {
  if (profiles$formal[j] == 1) Z[j, "formal"] <- 1
  if (profiles$size[j] != "Solo") {
    term <- paste0("tamano_empresa::", profiles$size[j])
    stopifnot(term %in% names(beta))
    Z[j, term] <- 1
    if (profiles$formal[j] == 1) {
      iterm <- intersect(c(paste0(term, ":formal"), paste0("formal:", term)), names(beta))
      stopifnot(length(iterm) == 1)
      Z[j, iterm] <- 1
    }
  }
}
profiles$profile <- seq_len(nrow(profiles))
profiles$log_profile <- as.vector(Z %*% beta)
profiles$gap_to_same_formality_solo <- profiles$log_profile - beta["formal"] * profiles$formal
reference <- read.csv(file.path(paper, "Paper/tables/regression_local_geography_formality_robustness.csv"))
reference <- reference[reference$model == "(4)" & reference$reference_size == "Solo", ]
ref_i <- match(reference$size, sizes)
Ci <- Z[ref_i, , drop = FALSE] - Z[rep(1, length(ref_i)), , drop = FALSE]
Cf <- Z[ref_i+9, , drop = FALSE] - Z[rep(10, length(ref_i)), , drop = FALSE]
validation <- data.frame(size = reference$size,
  informal_error = profiles$gap_to_same_formality_solo[ref_i] - reference$informal_estimate,
  formal_error = profiles$gap_to_same_formality_solo[ref_i + 9] - reference$formal_estimate,
  informal_se_error = sqrt(diag(Ci %*% V %*% t(Ci))) - reference$informal_se,
  formal_se_error = sqrt(diag(Cf %*% V %*% t(Cf))) - reference$formal_se)
stopifnot(max(abs(as.matrix(validation[, -1]))) < 1e-7)
write_table(validation, "coefficient_replication_check.csv")
write_table(profiles, "estimated_size_formality_profiles.csv")
write_table(data.frame(term = names(beta), estimate = beta, se = sqrt(diag(V))), "preferred_coefficients.csv")

t <- saved$target
audit <- data.frame(item = c("source_rows", "preferred_pooled_n", "pooled_clusters", "target_2025_n",
                            "target_invalid_hours", "target_pensioner_flag_1", "target_weight_sum"),
                    value = c(saved$raw_n, saved$nobs, saved$n_clusters, nrow(t),
                              sum(!is.finite(t$horas) | t$horas <= 0),
                              sum(t$pensionado_ocupado == 1, na.rm = TRUE), sum(t$fex)))
write_table(audit, "sample_audit.csv")
stopifnot(all(is.finite(t$ingreso_hora_real)), all(t$ingreso_hora_real > 0),
          max(abs(log(t$ingreso_hora_real) - t$log_ingreso_hora_real)) < 1e-5)
t <- t %>% filter(is.finite(horas), horas > 0)
t$origin <- match(as.character(t$tamano_empresa), sizes) + 9 * t$formal
t$eta_exp <- exp(t$eta)
smear <- weighted.mean(exp(t$log_residual), t$fex)
t$predicted_hourly <- t$eta_exp * smear
t$observed_weekly <- t$ingreso_hora_real * t$horas
t$predicted_weekly <- t$predicted_hourly * t$horas
stopifnot(all(is.finite(t$predicted_weekly)))

target_cells <- t %>% group_by(sector, depto, posicion_ocupacional_label, tamano_empresa, formal) %>%
  summarise(n = n(), sum_w = sum(fex), neff = sum(fex)^2 / sum(fex^2), .groups = "drop")
support_key <- function(sector, depto, occupation, size, formal) {
  paste(sector, depto, occupation, size, formal, sep = "|")
}
target_cells$key <- with(target_cells, support_key(sector, depto, posicion_ocupacional_label, tamano_empresa, formal))
pooled_cells <- saved$pooled_cells
pooled_cells$key <- with(pooled_cells, support_key(sector, depto, posicion_ocupacional_label, tamano_empresa, formal))
support_counts <- function(dest) {
  k <- support_key(t$sector, t$depto, t$posicion_ocupacional_label,
                   profiles$size[dest], profiles$formal[dest])
  a <- match(k, target_cells$key)
  p <- match(k, pooled_cells$key)
  data.frame(n2025 = ifelse(is.na(a), 0, target_cells$n[a]),
             neff2025 = ifelse(is.na(a), 0, target_cells$neff[a]),
             npooled = ifelse(is.na(p), 0, pooled_cells$n[p]))
}
groups <- t %>% group_by(tamano_empresa, formal) %>% summarise(
  n = n(), sum_w = sum(fex), neff = sum(fex)^2/sum(fex^2),
  hourly_observed = weighted.mean(ingreso_hora_real, fex),
  hourly_predicted = weighted.mean(predicted_hourly, fex),
  weekly_observed = weighted.mean(observed_weekly, fex),
  weekly_predicted = weighted.mean(predicted_weekly, fex),
  hours = weighted.mean(horas, fex), .groups = "drop")
groups$worker_share_pct <- 100 * groups$sum_w / sum(t$fex)
write_table(groups, "baseline_groups_2025.csv")
write_table(t %>% group_by(posicion_ocupacional_label, formal, tamano_empresa) %>%
              summarise(n = n(), sum_w = sum(fex), .groups = "drop"), "occupation_size_formality_counts.csv")
write_table(target_cells %>% select(-key), "destination_support_cells_2025.csv")

best_i <- which.max(profiles$log_profile[1:9])
best_f <- 9 + which.max(profiles$log_profile[10:18])
scenarios <- list(
  formalize_same_size = ifelse(t$formal == 0, t$origin + 9L, t$origin),
  formal_to_101 = ifelse(t$formal == 1, 18L, t$origin),
  informal_to_101 = ifelse(t$formal == 0, 9L, t$origin),
  combined_formal_101 = rep(18L, nrow(t)),
  informal_to_best = ifelse(t$formal == 0, best_i, t$origin),
  both_to_best_fixed_status = ifelse(t$formal == 0, best_i, best_f)
)
results <- list()
breakdowns <- list()
diagnostics <- list()
critical <- qt(0.975, df = saved$df_t)
metrics <- c("hourly", "weekly")
methods <- c("predicted_common_smear", "observed_residual_preserved")
support_rules <- c("unrestricted", "pooled_n30", "target_n10", "target_n30", "target_n50", "target_neff30")

summarize_transition <- function(dest, scenario, support_rule, method, metric, subset) {
  y <- if (method == "predicted_common_smear") t$predicted_hourly else t$ingreso_hora_real
  if (metric == "weekly") y <- y * t$horas
  sel <- if (subset == "all") rep(TRUE, nrow(t)) else dest != t$origin
  if (!any(sel)) return(NULL)
  df <- data.frame(origin = t$origin[sel], dest = dest[sel], mass = (t$fex*y)[sel]) %>%
    group_by(origin, dest) %>% summarise(mass = sum(mass), .groups = "drop")
  C <- Z[df$dest, , drop = FALSE] - Z[df$origin, , drop = FALSE]
  delta <- as.vector(C %*% beta)
  multipliers <- exp(delta)
  denom <- sum(df$mass)
  gain <- sum(df$mass * expm1(delta)) / denom
  grad <- colSums(C * as.vector(df$mass * multipliers)) / denom
  se <- sqrt(as.numeric(t(grad) %*% V %*% grad))
  row <- data.frame(scenario = scenario, support = support_rule, method = method, metric = metric,
    population = subset, gain_pct = 100*gain, ci_low_pct = 100*(gain-critical*se),
    ci_high_pct = 100*(gain+critical*se), baseline_mean = denom/sum(t$fex[sel]),
    counterfactual_mean = denom*(1+gain)/sum(t$fex[sel]),
    moved_worker_share_pct = 100*sum(t$fex[dest != t$origin])/sum(t$fex),
    denominator_worker_share_pct = 100*sum(t$fex[sel])/sum(t$fex))
  # Independent individual-level identity check against the aggregated calculation.
  direct <- sum((t$fex*y)[sel] * exp(profiles$log_profile[dest[sel]] - profiles$log_profile[t$origin[sel]])) / denom - 1
  stopifnot(abs(gain-direct) < 1e-10)
  row
}

for (scenario in names(scenarios)) {
  message("Scenario: ", scenario)
  intended <- scenarios[[scenario]]
  moved <- intended != t$origin
  counts <- support_counts(intended)
  eligibility <- list(
    unrestricted = rep(TRUE, nrow(t)), pooled_n30 = counts$npooled >= 30,
    target_n10 = counts$n2025 >= 10, target_n30 = counts$n2025 >= 30,
    target_n50 = counts$n2025 >= 50, target_neff30 = counts$neff2025 >= 30
  )
  diagnostics[[scenario]] <- data.frame(
    scenario = scenario, intended_move_share_pct = 100*sum(t$fex[moved])/sum(t$fex),
    destination_absent_2025_pct_of_intended = 100*sum(t$fex[moved & counts$n2025 == 0])/sum(t$fex[moved]),
    destination_lt30_2025_pct_of_intended = 100*sum(t$fex[moved & counts$n2025 < 30])/sum(t$fex[moved]),
    destination_absent_pooled_pct_of_intended = 100*sum(t$fex[moved & counts$npooled == 0])/sum(t$fex[moved]))
  for (rule in support_rules) {
    dest <- ifelse(eligibility[[rule]], intended, t$origin)
    for (method in methods) for (metric in metrics) for (population in c("all", "movers")) {
      results[[length(results)+1L]] <- summarize_transition(dest, scenario, rule, method, metric, population)
    }
    b <- t %>% mutate(dest = dest, moved = dest != origin,
                      wage_multiplier = exp(profiles$log_profile[dest] - profiles$log_profile[origin])) %>%
      group_by(formal, tamano_empresa) %>% summarise(
        worker_share_pct = 100*sum(fex)/sum(t$fex),
        moved_share_within_origin_pct = 100*sum(fex[moved])/sum(fex),
        observed_weekly_gain_pct = 100*sum(fex*observed_weekly*(wage_multiplier-1))/sum(fex*observed_weekly),
        predicted_weekly_gain_pct = 100*sum(fex*predicted_weekly*(wage_multiplier-1))/sum(fex*predicted_weekly),
        contribution_to_all_predicted_weekly_gain_pp = 100*sum(fex*predicted_weekly*(wage_multiplier-1))/sum(t$fex*t$predicted_weekly),
        .groups = "drop") %>% mutate(scenario = scenario, support = rule)
    breakdowns[[length(breakdowns)+1L]] <- b
  }
}
result <- bind_rows(results)
# The affected formality group includes workers already at the destination.
group_rows <- lapply(seq_len(nrow(result)), function(j) {
  r <- result[j, ]
  if (r$population != "all") return(NULL)
  keep <- switch(r$scenario,
    formalize_same_size = t$formal == 0,
    informal_to_101 = t$formal == 0,
    informal_to_best = t$formal == 0,
    formal_to_101 = t$formal == 1,
    rep(TRUE, nrow(t)))
  y <- if (r$method == "predicted_common_smear") t$predicted_hourly else t$ingreso_hora_real
  if (r$metric == "weekly") y <- y*t$horas
  scale <- sum(t$fex*y)/sum((t$fex*y)[keep])
  r$population <- "target_group"
  r$gain_pct <- r$gain_pct*scale
  r$ci_low_pct <- r$ci_low_pct*scale
  r$ci_high_pct <- r$ci_high_pct*scale
  r$baseline_mean <- weighted.mean(y[keep], t$fex[keep])
  r$counterfactual_mean <- r$baseline_mean*(1+r$gain_pct/100)
  r$denominator_worker_share_pct <- 100*sum(t$fex[keep])/sum(t$fex)
  r
})
result <- bind_rows(result, bind_rows(group_rows))
write_table(result, "scenario_results.csv")
write_table(bind_rows(breakdowns), "scenario_origin_breakdown.csv")
write_table(bind_rows(diagnostics), "support_diagnostics.csv")

# Joint uncertainty of the estimated profiles, with post-selection uncertainty kept descriptive.
set.seed(20261010)
active <- which(colSums(abs(Z)) > 0)
E <- eigen(V[active, active], symmetric = TRUE)
stopifnot(min(E$values) > -1e-10)
B <- matrix(rnorm(20000 * length(active)), ncol = length(active)) %*%
  t(E$vectors %*% diag(sqrt(pmax(E$values, 0))))
B <- sweep(B, 2, beta[active], "+")
draw_profiles <- B %*% t(Z[, active, drop = FALSE])
win_i <- max.col(draw_profiles[, 1:9], ties.method = "first")
win_f <- max.col(draw_profiles[, 10:18], ties.method = "first")
write_table(data.frame(size = sizes,
  informal_frequency_max = tabulate(win_i, nbins = 9)/length(win_i),
  formal_frequency_max = tabulate(win_f, nbins = 9)/length(win_f)), "best_destination_uncertainty.csv")

contrast <- function(a, b, label) {
  c <- Z[a, ]-Z[b, ]
  est <- sum(c*beta)
  se <- sqrt(as.numeric(t(c)%*%V%*%c))
  data.frame(comparison = label, estimate_log = est, se_log = se,
             gap_pct = 100*expm1(est), ci_low_pct = 100*expm1(est-critical*se),
             ci_high_pct = 100*expm1(est+critical*se))
}
write_table(bind_rows(contrast(8, 9, "Informal 51-100 versus 101+"),
                     contrast(18, 10, "Formal 101+ versus solo"),
                     contrast(9, 1, "Informal 101+ versus solo")), "key_pairwise_contrasts.csv")
meta <- c(
  paste("Run:", Sys.time()), paste("Data:", data_path),
  paste("Input bytes:", signature$size), paste("Input modified:", data_info$mtime),
  paste("Paper commit:", system2("git", c("-C", shQuote(paper), "rev-parse", "HEAD"), stdout = TRUE)),
  paste("Preferred pooled observations:", saved$nobs), paste("Cluster count:", saved$n_clusters),
  paste("Target observations:", nrow(t)), paste("Common weighted smearing factor:", smear),
  paste("Point-estimate best informal size:", sizes[best_i]),
  paste("Point-estimate best formal size:", sizes[best_f-9]),
  paste("Formula:", paste(saved$formula, collapse = " ")),
  "Source microdata are read-only. Outputs are written only to the selected replication output directory.",
  "Weekly income is real hourly labor income multiplied by unchanged weekly hours.",
  "Survey weights are used for averages and relative totals, not reported as unique annual worker counts.",
  "Common-smearing predictions assume a common residual exponential moment. It cancels from percentage gains.",
  "The residual-preserving sensitivity multiplies observed hourly income by exp(destination-origin log contrast).",
  "Intervals propagate the clustered coefficient covariance through the delta method, conditional on baseline incomes, hours, weights, and destination choice.",
  "Intervals omit baseline/composition uncertainty, destination selection, structural uncertainty, and equilibrium effects.",
  "Support screens count observations in destination size/formality by sector, department, and occupational position. They are not full common-support proofs.",
  "Screened-out workers stay at origin. All-worker denominators remain unchanged across support rules.",
  "Best-destination frequencies are multivariate-normal coefficient simulations, not probabilities of policy optimality.",
  saved$session)
writeLines(meta, file.path(out, "run_metadata.txt"))
message("DONE: ", out)
print(result %>% filter(population == "all", metric == "weekly", method == "predicted_common_smear",
                       support %in% c("unrestricted", "target_n30")), row.names = FALSE)
