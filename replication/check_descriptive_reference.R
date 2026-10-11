if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages(library(dplyr))
d <- readRDS(file.path(paper, "build/regression_sample.rds"))
ep <- d %>% filter(as.character(anio) %in% c("2008", "2025"))
cells <- ep %>% group_by(anio, tamano_empresa) %>% summarise(
  weight = sum(fex), hourly_income = weighted.mean(exp(log_ingreso_hora_real), fex), .groups = "drop")
total <- ep %>% group_by(anio) %>% summarise(tamano_empresa = "All workers", weight = sum(fex),
  hourly_income = weighted.mean(exp(log_ingreso_hora_real), fex), .groups = "drop")
cells <- cells %>% mutate(tamano_empresa = as.character(tamano_empresa)) %>% bind_rows(total) %>%
  group_by(anio) %>% mutate(share = 100*weight/weight[tamano_empresa == "All workers"],
    ratio_to_solo = hourly_income/hourly_income[tamano_empresa == "Solo"]) %>% ungroup()
write.csv(cells, file.path(paper, "replication/regression_output/descriptive_reference_check.csv"), row.names = FALSE)
message("Recomputed endpoint descriptive means and employment shares from the current common sample.")
