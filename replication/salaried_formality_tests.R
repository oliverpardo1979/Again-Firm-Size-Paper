# Post-estimation only: the saved models contain coefficients and covariances, not microdata.
local({
  script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  paper <- dirname(dirname(normalizePath(script, winslash = "/")))
  out <- file.path(paper, "replication/salaried_output")
  models <- readRDS(file.path(out, "aggregate_models.rds"))
  sizes <- c("2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
  profile <- function(m, size, formal) {
    z <- setNames(numeric(length(m$b)), names(m$b))
    if (size == m$base) return(z)
    term <- paste0("tamano_empresa::", size)
    stopifnot(term %in% names(z))
    z[term] <- 1
    if (formal) {
      term <- intersect(c(paste0(term, ":formal"), paste0("formal:", term)), names(z))
      stopifnot(length(term) == 1)
      z[term] <- 1
    }
    z
  }
  rows <- list()
  for (sample in names(models)) for (sector in c(FALSE, TRUE)) {
    m <- models[[sample]]
    V <- if (sector) m$V_sector else m$V
    df <- if (sector) m$df_sector else m$df
    A <- do.call(rbind, lapply(sizes, function(size)
      profile(m, size, TRUE)-profile(m, "Solo", TRUE)-
        profile(m, size, FALSE)+profile(m, "Solo", FALSE)))
    difference <- drop(A %*% m$b)
    covariance <- A %*% V %*% t(A)
    stopifnot(qr(covariance)$rank == length(sizes))
    estimate <- tail(difference, 1)
    se <- sqrt(tail(diag(covariance), 1))
    statistic <- drop(crossprod(difference, solve(covariance, difference))) / length(sizes)
    rows[[length(rows)+1L]] <- data.frame(sample = sample,
      clustering = if (sector) "Sector" else "Sector-department",
      test = "101+/solo equality", estimate = estimate, std.error = se,
      statistic = estimate/se, df_num = NA, df_den = df,
      p.value = 2*pt(abs(estimate/se), df, lower.tail = FALSE))
    rows[[length(rows)+1L]] <- data.frame(sample = sample,
      clustering = if (sector) "Sector" else "Sector-department",
      test = "Joint profile equality", estimate = NA, std.error = NA,
      statistic = statistic, df_num = length(sizes), df_den = df,
      p.value = pf(statistic, length(sizes), df, lower.tail = FALSE))
  }
  results <- do.call(rbind, rows)
  write.csv(results, file.path(out, "formality_equality_tests.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  print(results)
})
