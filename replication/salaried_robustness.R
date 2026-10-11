args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
cjc <- file.path(dirname(paper), "CJC-Monitor")
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(dplyr); library(fixest)})
source(file.path(paper, "replication/harmonize_occupation.R"))
setFixest_nthreads(4)
out <- file.path(paper, "replication/salaried_output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
d <- readRDS(file.path(paper, "build/regression_sample.rds"))
stopifnot(identical(attr(d, "cache_signature")[[3]], occupation_harmonization_version))
stopifnot(all(d$wage_employee == (d$occupation_harmonized_code %in% c(1, 2, 3, 8))))
write_csv(d %>% count(anio, occupation_raw_code, occupation_harmonized_code,
  posicion_ocupacional_label, wage_employee, name = "observations"), "occupation_audit")
sizes <- levels(d$tamano_empresa)
cell_n <- tabulate(as.integer(d$sector_depto_year), nbins = nlevels(d$sector_depto_year))
d <- d[cell_n[as.integer(d$sector_depto_year)] > 1L, ]
stopifnot(nrow(d) == 5268375L)
employee <- d[d$wage_employee, ]
before_singletons <- nrow(employee)
cell_n <- tabulate(as.integer(employee$sector_depto_year), nbins = nlevels(employee$sector_depto_year))
employee <- employee[cell_n[as.integer(employee$sector_depto_year)] > 1L, ]
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1)
rhs <- paste0("i(tamano_empresa, ref = '11-19') * formal + mujer + edad + edad2 + ",
  "i(educacion, ref = '", edu, "') + i(posicion_ocupacional_label) | sector_depto_year")
message("Estimating salaried-only specification on ", nrow(employee), " observations")
m <- feols(as.formula(paste("log_ingreso_hora_real ~", rhs)), data = employee,
  weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE)
stopifnot(nobs(m) == nrow(employee))
models <- list(Salaried = list(b = coef(m), V = vcov(m), V_sector = vcov(m, cluster = ~sector),
  df = degrees_freedom(m, "t"), df_sector = degrees_freedom(m, "t", vcov = ~sector),
  n = nobs(m), r2 = unname(fitstat(m, "r2")[[1]]), base = "11-19"))
rm(m)
gc()
# Verify the intermediate-base contrasts against an independently fitted solo base.
rebased <- feols(as.formula(paste("log_ingreso_hora_real ~", sub("ref = '11-19'", "ref = 'Solo'", rhs, fixed = TRUE))),
  data = employee, weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE)
rebased_model <- list(b = coef(rebased), V = vcov(rebased), base = "Solo",
  df = degrees_freedom(rebased, "t"))
rm(rebased)
gc()
preferred <- readRDS(file.path(paper, "replication/preferred_output/aggregate_models.rds"))$preferred
preferred$base <- "Solo"
models <- c(list(All = preferred), models)
unit <- function(m, term) {
  stopifnot(term %in% names(m$b))
  z <- setNames(numeric(length(m$b)), names(m$b))
  z[term] <- 1
  z
}
profile <- function(m, size, formal) {
  if (size == m$base) return(setNames(numeric(length(m$b)), names(m$b)))
  term <- paste0("tamano_empresa::", size)
  z <- unit(m, term)
  if (formal) {
    interaction <- intersect(c(paste0(term, ":formal"), paste0("formal:", term)), names(m$b))
    stopifnot(length(interaction) == 1)
    z <- z + unit(m, interaction)
  }
  z
}
contrast <- function(m, z, sector = FALSE) {
  V <- if (sector) m$V_sector else m$V
  df <- if (sector) m$df_sector else m$df
  b <- sum(z*m$b)
  se <- sqrt(drop(t(z) %*% V %*% z))
  critical <- qt(.975, df)
  data.frame(estimate = b, std.error = se, p.value = 2*pt(abs(b/se), df, lower.tail = FALSE),
    premium = 100*expm1(b), ci_low = 100*expm1(b-critical*se), ci_high = 100*expm1(b+critical*se), df = df)
}
rows <- list()
for (name in names(models)) for (base in c("Solo", "101+", "11-19")) for (size in setdiff(sizes, base))
  for (f in 0:1) for (s in c(FALSE, TRUE)) {
    m <- models[[name]]
    rows[[length(rows)+1L]] <- cbind(sample = name, reference = base, size = size,
      group = if (f) "Formal" else "Informal", clustering = if (s) "Sector" else "Sector-department",
      contrast(m, profile(m, size, f)-profile(m, base, f), s))
  }
write_csv(bind_rows(rows), "contrasts")
checks <- list()
for (size in sizes[-1]) for (f in 0:1) {
  m <- models$Salaried
  a <- contrast(m, profile(m, size, f)-profile(m, "Solo", f))
  b <- contrast(rebased_model, profile(rebased_model, size, f))
  checks[[length(checks)+1L]] <- data.frame(size = size, formal = f,
    coef_error = a$estimate-b$estimate, se_error = a$std.error-b$std.error)
}
checks <- bind_rows(checks)
stopifnot(max(abs(checks$coef_error), abs(checks$se_error)) < 1e-7)
write_csv(checks, "reference_invariance_check")
rows <- list()
for (name in names(models)) {
  m <- models[[name]]
  for (term in names(m$b)) rows[[length(rows)+1L]] <- cbind(sample = name, term = term, contrast(m, unit(m, term)))
  vv <- bind_rows(lapply(c("Sector-department", "Sector"), function(clustering) {
    x <- as.data.frame(as.table(if (clustering == "Sector") m$V_sector else m$V), stringsAsFactors = FALSE)
    names(x) <- c("term1", "term2", "covariance")
    cbind(clustering = clustering, x)
  }))
  write_csv(vv, paste0("covariance_", name))
}
write_csv(bind_rows(rows), "coefficients")
write_csv(bind_rows(lapply(names(models), function(name) {
  m <- models[[name]]
  data.frame(sample = name, n = m$n, r2 = m$r2, df = m$df, df_sector = m$df_sector, base = m$base)
})), "models")
counts <- bind_rows(lapply(c("All", "Salaried"), function(name) {
  x <- if (name == "All") d else employee
  x %>% group_by(tamano_empresa, formal) %>% summarise(observations = n(), .groups = "drop") %>%
    mutate(sample = name)
}))
write_csv(counts, "sample_counts")
write_csv(data.frame(full_sample = nrow(d), salaried_candidates = before_singletons,
  additional_singletons_removed = before_singletons-nrow(employee), salaried_estimation_sample = nrow(employee)), "sample_audit")
# Preserve the effect of the coding correction separately from sample restriction.
old_path <- file.path(paper, "build/occupation_previous_preferred_models.rds")
if (file.exists(old_path)) {
  previous <- readRDS(old_path)
  old <- previous$preferred
  old$base <- "Solo"
  changes <- list()
  for (size in sizes[-1]) for (f in 0:1) {
    a <- contrast(old, profile(old, size, f))
    b <- contrast(preferred, profile(preferred, size, f))
    changes[[length(changes)+1L]] <- data.frame(size = size, group = if (f) "Formal" else "Informal",
      premium_before = a$premium, premium_after = b$premium, change_pp = b$premium-a$premium,
      p_before = a$p.value, p_after = b$p.value)
  }
  write_csv(bind_rows(changes), "harmonization_impact")
  current <- readRDS(file.path(paper, "replication/preferred_output/aggregate_models.rds"))
  unchanged <- c("sector_year", "sector_dept_year", grep("^year", names(current), value = TRUE), "elasticity_raw")
  invariance <- bind_rows(lapply(unchanged, function(name) {
    # Within a year the correction only renames categories. These contrasts must not change.
    terms <- intersect(names(previous[[name]]$b), names(current[[name]]$b))
    terms <- terms[!grepl("posicion_ocupacional", terms)]
    data.frame(model = name, coefficients_checked = length(terms),
      max_coef_error = max(abs(previous[[name]]$b[terms]-current[[name]]$b[terms])),
      max_covariance_error = max(abs(previous[[name]]$V[terms, terms]-current[[name]]$V[terms, terms])))
  }))
  stopifnot(max(invariance$max_coef_error, invariance$max_covariance_error) < 1e-7)
  write_csv(invariance, "unaffected_model_checks")
}
saveRDS(models, file.path(out, "aggregate_models.rds"))
source(file.path(paper, "replication/salaried_formality_tests.R"))
writeLines(c(paste("Occupation harmonization:", occupation_harmonization_version),
  "Employees: private-sector, government, domestic, and day laborers. Formal and informal workers retained.",
  "Same pooled preferred controls. One size-by-formality regression for the employee sample.",
  "Same wage/hour measurement. 11-19 is the fitted reference; other bases are linear contrasts.",
  "Singleton sector-department-year cells are removed after restricting the sample.",
  "Two-sided cluster-t inference under sector-department and sector clustering.",
  trimws(capture.output(sessionInfo()), which = "right")), file.path(out, "provenance.txt"))
message("Salaried robustness complete: ", nrow(employee), " observations")
