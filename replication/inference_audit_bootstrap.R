# Standalone inference audit. The manuscript and its existing outputs are untouched.
.libPaths(c("build/inference_Rlib", "../CJC-Monitor/.Rlib", .libPaths()))
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
suppressPackageStartupMessages({library(fwildclusterboot); library(fixest)})
out <- "replication/inference_audit_output"
cache <- "build/inference_audit"
tests <- read.csv(file.path(out, "contrasts.csv"), check.names = FALSE)
conventional <- read.csv(file.path(out, "conventional.csv"), check.names = FALSE)
B <- 9999L
selected <- unique(tests$contrast)
seed <- 20261018L
rows <- list()
verification <- list()
for (model in c("preferred", "endpoints", "elasticity")) {
  d <- read.csv(file.path(cache, paste0(model, "_compressed.csv")), check.names = FALSE)
  d$sector <- match(d$sector, unique(d$sector))
  terms <- grep("^v[0-9]+$", names(d), value = TRUE)
  fit <- lm(reformulate(terms, response = "y", intercept = FALSE), data = d)
  estimates <- read.csv(file.path(out, paste0(model, "_coefficients.csv")))
  stopifnot(max(abs(coef(fit)-estimates$estimate)) < 1e-7)
  for (label in intersect(selected, unique(tests$contrast[tests$model == model]))) {
    z <- tests[tests$model == model & tests$contrast == label, ]
    for (clustering in c("Sector", "Department", "Two-way sector + department")) {
      ids <- switch(clustering, Sector = "sector", Department = "depto", c("sector", "depto"))
      bootcluster <- if (length(ids) == 2L) "min" else ids
      stamp <- paste(model, label, clustering, sep = " | ")
      message(format(Sys.time()), " ", stamp)
      set.seed(seed)
      dqrng::dqset.seed(seed)
      w <- character()
      ans <- withCallingHandlers(boottest(fit, param = z$term, R = z$weight, r = 0,
        B = B, clustid = ids, bootcluster = bootcluster, conf_int = FALSE,
        impose_null = TRUE, type = "rademacher", bootstrap_type = "fnw11",
        p_val_type = "two-tailed", nthreads = 2,
        ssc = boot_ssc(adj = FALSE, cluster.adj = TRUE, cluster.df = "min")),
        warning = function(e) {w <<- c(w, conditionMessage(e)); invokeRestart("muffleWarning")})
      original <- conventional[conventional$model == model & conventional$contrast == label &
                                  conventional$clustering == clustering, ]
      stopifnot(nrow(original) == 1L, abs(ans$point_estimate-original$estimate) < 1e-7)
      # N/(N-K) is a common positive scalar in t and t*, so it cancels from the bootstrap p-value.
      info <- read.csv(file.path(out,"cluster_sizes.csv"))
      n <- info$n[info$model == model][1]
      k <- length(terms)
      expected_t <- original$estimate/original$se * sqrt((n-1)/(n-k-1))
      verification[[length(verification)+1L]] <- data.frame(model, contrast=label, clustering,
        t_error = as.numeric(ans$t_stat)-expected_t)
      stopifnot(abs(as.numeric(ans$t_stat)-expected_t) < 1e-5)
      good <- is.finite(ans$t_boot)
      rows[[length(rows)+1L]] <- data.frame(model, contrast=label, clustering,
        estimate=ans$point_estimate, p_conventional=original$p, p_wild=ans$p_val,
        B_requested=B, B_returned=ans$boot_iter, finite_boot_t=sum(good), nonfinite_boot_t=sum(!good),
        discarded_boot_t=ans$boot_iter-length(ans$t_boot),
        seed=seed, weights="Rademacher", null_imposed=TRUE,
        bootstrap_clusters=if (length(ids)==2L) "sector (minimum cluster count)" else ids,
        warnings=paste(unique(w),collapse=" | "))
      write.csv(do.call(rbind,rows),file.path(out,"wild_bootstrap.csv"),row.names=FALSE)
      write.csv(do.call(rbind,verification),file.path(out,"bootstrap_validation.csv"),row.names=FALSE)
      message("p conventional=", signif(original$p,4), " p WCR=", signif(ans$p_val,4))
    }
  }
}
writeLines(c("WCR11, null imposed, two-sided, Rademacher weights, 9999 replications.",
  "Seed 20261018. Multiway covariance uses the minimum cluster correction.",
  "Two-way bootstrap draws weights by sector, the smaller dimension (17 clusters).",
  "WLS fixed effects are removed exactly through weighted within-cell moments.",
  "All clustering dimensions contain complete sector-department-year FE cells.",
  "The compressed square-root representation preserves cluster X'X and X'y.",
  "Finite-N scaling cancels between observed and bootstrap t-statistics.",
  "Invalid bootstrap t-statistics dropped internally by the package are counted in discarded_boot_t.",
  trimws(capture.output(sessionInfo()), which = "right")),file.path(out,"bootstrap_provenance.txt"))
