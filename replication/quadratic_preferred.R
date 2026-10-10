args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
cjc <- file.path(dirname(paper), "CJC-Monitor")
input <- if (length(args)) args[1] else file.path(cjc, "Datos/Processed/Paper-GEIH_base_modelo_personas_2008_2025.dta")
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr); library(fixest)})
setFixest_nthreads(4)
out <- file.path(paper, "replication/quadratic_output")
cache <- file.path(paper, "build/quadratic_preferred")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
assignments <- c(101, 150, 250)
signature <- c(file.info(input)$size, as.numeric(file.info(input)$mtime))
sample_path <- file.path(paper, "build/regression_sample.rds")
d <- if (file.exists(sample_path)) readRDS(sample_path) else NULL
if (is.null(d) || !identical(attr(d, "cache_signature"), signature)) {
  cols <- c("anio", "depto", "edad", "sector", "tamano_empresa", "educacion", "posicion_ocupacional_label", "mujer", "formal", "fex", "log_ingreso_hora_real")
  d <- read_dta(input, col_select = all_of(cols)) %>%
    mutate(across(c(anio, depto, sector, educacion, posicion_ocupacional_label), factor),
      edad = as.numeric(edad), edad2 = edad^2, tamano_empresa = factor(tamano_empresa, levels = sizes)) %>%
    filter(is.finite(log_ingreso_hora_real), !is.na(tamano_empresa), !is.na(mujer), is.finite(edad),
      !is.na(educacion), !is.na(formal), !is.na(sector), !is.na(anio), is.finite(fex), fex > 0) %>%
    mutate(sector_depto = interaction(sector, depto, drop = TRUE),
      sector_depto_year = interaction(sector, depto, anio, drop = TRUE))
}
stopifnot(!anyNA(d$depto), !anyNA(d$posicion_ocupacional_label), !any(as.character(d$anio) == "2020"))
cell_n <- tabulate(as.integer(d$sector_depto_year), nbins = nlevels(d$sector_depto_year))
d <- d[cell_n[as.integer(d$sector_depto_year)] > 1L, ]
stopifnot(nrow(d) == 5268375L)
preferred <- readRDS(file.path(paper, "replication/preferred_output/aggregate_models.rds"))$preferred
input_md5 <- unname(tools::md5sum(input))
stopifnot(paste("Input MD5:", input_md5) %in% readLines(file.path(paper, "replication/preferred_output/provenance.txt")))
stopifnot(preferred$n == nrow(d))
edu <- grep("secundaria", levels(d$educacion), value = TRUE, ignore.case = TRUE)
stopifnot(length(edu) == 1)
rhs <- paste0("(z + z2) * formal + mujer + edad + edad2 + i(educacion, ref = '", edu,
  "') + i(posicion_ocupacional_label) | sector_depto_year")
unit <- function(m, candidates) {
  term <- intersect(candidates, names(m$b))
  stopifnot(length(term) == 1L)
  v <- setNames(numeric(length(m$b)), names(m$b))
  v[term] <- 1
  v
}
contrast <- function(m, v) {
  b <- sum(v*m$b)
  se <- sqrt(max(0, drop(t(v) %*% m$V %*% v)))
  critical <- qt(.975, m$df)
  data.frame(estimate = b, std.error = se, df = m$df,
    p.value = if (se > 0) 2*pt(abs(b/se), m$df, lower.tail = FALSE) else NA_real_,
    conf.low = b-critical*se, conf.high = b+critical*se,
    premium = 100*expm1(b), ci_low = 100*expm1(b-critical*se), ci_high = 100*expm1(b+critical*se))
}
cat_map <- function(f) do.call(rbind, lapply(sizes[-1], function(size) {
  term <- paste0("tamano_empresa::", size)
  v <- unit(preferred, term)
  if (f) v <- v + unit(preferred, c(paste0(term, ":formal"), paste0("formal:", term)))
  v
}))
maps <- list(Informal = cat_map(0), Formal = cat_map(1))
models <- list()
coefficients <- curves <- points <- tests <- summaries <- raw <- covariance <- list()
for (top in assignments) {
  name <- paste0("quadratic_", top)
  key <- list(version = 1L, signature = signature, rhs = rhs, n = nrow(d), top = top)
  path <- file.path(cache, paste0(name, ".rds"))
  saved <- if (file.exists(path)) readRDS(path) else NULL
  assigned <- c(1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, top)
  if (!is.null(saved) && identical(saved$key, key)) {
    message("Reusing ", name)
    m <- saved$model
  } else {
    message("Estimating ", name, " with preferred controls on ", nrow(d), " observations")
    d$z <- log(assigned[as.integer(d$tamano_empresa)])
    d$z2 <- d$z^2
    fit <- feols(as.formula(paste("log_ingreso_hora_real ~", rhs)), data = d,
      weights = ~fex, cluster = ~sector_depto, mem.clean = TRUE)
    m <- list(b = coef(fit), V = vcov(fit), V_sector = vcov(fit, cluster = ~sector),
      df = degrees_freedom(fit, "t"), df_sector = degrees_freedom(fit, "t", vcov = ~sector),
      n = nobs(fit), r2 = unname(fitstat(fit, "r2")[[1]]))
    stopifnot(m$n == preferred$n, m$df == preferred$df)
    saveRDS(list(key = key, model = m), path)
    rm(fit)
    gc()
  }
  models[[name]] <- m
  for (f in 0:1) {
    group <- if (f) "Formal" else "Informal"
    a1 <- unit(m, "z")
    a2 <- unit(m, "z2")
    if (f) {
      a1 <- a1 + unit(m, c("z:formal", "formal:z"))
      a2 <- a2 + unit(m, c("z2:formal", "formal:z2"))
    }
    for (term in c("linear", "quadratic")) coefficients[[length(coefficients)+1L]] <-
      cbind(top = top, group = group, term = term, contrast(m, if (term == "linear") a1 else a2))
    for (z in seq(0, log(top), length.out = 201)) curves[[length(curves)+1L]] <-
      cbind(top = top, group = group, z = z, size_value = exp(z), contrast(m, z*a1+z^2*a2))
    for (j in seq_along(sizes)) points[[length(points)+1L]] <-
      cbind(top = top, group = group, size = sizes[j], size_value = assigned[j],
        contrast(m, log(assigned[j])*a1+log(assigned[j])^2*a2))
    b1 <- sum(a1*m$b)
    b2 <- sum(a2*m$b)
    turn <- -b1/(2*b2)
    summaries[[length(summaries)+1L]] <- data.frame(top = top, group = group, linear = b1, quadratic = b2,
      turning_size = exp(turn), turn_within_support = turn > 0 && turn < log(top),
      elasticity_solo = b1, elasticity_top = b1+2*b2*log(top), n = m$n, r2 = m$r2)
  }
  # Orthogonal complements impose six restrictions per eight-category profile.
  z <- log(assigned[-1])
  M <- cbind(z, z^2)
  Q <- qr.Q(qr(M), complete = TRUE)
  L <- t(Q[, 3:8, drop = FALSE])
  stopifnot(max(abs(L %*% M)) < 1e-10)
  restrictions <- lapply(maps, function(A) L %*% A)
  restrictions$Joint <- rbind(restrictions$Informal, restrictions$Formal)
  for (group in names(restrictions)) for (sector in c(FALSE, TRUE)) {
    R <- restrictions[[group]]
    V <- if (sector) preferred$V_sector else preferred$V
    df <- if (sector) preferred$df_sector else preferred$df
    r <- drop(R %*% preferred$b)
    RV <- R %*% V %*% t(R)
    stopifnot(qr(RV)$rank == nrow(R))
    W <- drop(t(r) %*% solve(RV, r))
    q <- nrow(R)
    tests[[length(tests)+1L]] <- data.frame(top = top, group = group,
      clustering = if (sector) "Sector" else "Sector-department", restrictions = q,
      wald = W, F_statistic = W/q, df_num = q, df_den = df,
      p.value = pf(W/q, q, df, lower.tail = FALSE))
  }
  raw[[length(raw)+1L]] <- bind_rows(lapply(names(m$b), function(term)
    cbind(model = name, top = top, term = term, contrast(m, unit(m, term)))))
  for (clustering in c("Sector-department", "Sector")) {
    v <- as.data.frame(as.table(if (clustering == "Sector") m$V_sector else m$V), stringsAsFactors = FALSE)
    names(v) <- c("term1", "term2", "covariance")
    covariance[[length(covariance)+1L]] <- cbind(model = name, top = top, clustering = clustering, v)
  }
}
write_csv(bind_rows(coefficients), "coefficients")
write_csv(bind_rows(raw), "raw_coefficients")
write_csv(bind_rows(covariance), "covariances")
write_csv(bind_rows(points), "category_predictions")
write_csv(bind_rows(curves), "curves")
write_csv(bind_rows(tests), "restriction_tests")
write_csv(bind_rows(summaries), "summaries")
saveRDS(models, file.path(out, "aggregate_models.rds"))
writeLines(c(paste("Input MD5:", input_md5), paste("N:", nrow(d)),
  "Quadratic only. One interacted regression per assigned 101+ size (101, 150, 250).",
  "Same preferred controls, estimation sample, GEIH weights, and sector-department inference.",
  "Wald F tests use the unrestricted preferred categorical model: 6 restrictions per group, 12 jointly.",
  "Sector-clustering sensitivity holds all point estimates fixed. No microdata are published.",
  trimws(capture.output(sessionInfo()), which = "right")), file.path(out, "provenance.txt"))
print(bind_rows(summaries))
print(bind_rows(tests))
