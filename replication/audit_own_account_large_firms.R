args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
cjc <- file.path(dirname(paper), "CJC-Monitor")
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr)})
source(file.path(paper, "replication/harmonize_occupation.R"))
# Historical input. The primary-income reconstruction retains the original person keys.
input <- if (length(args)) args[1] else file.path(cjc, "Datos/Processed/Paper-GEIH_base_modelo_personas_2008_2025.dta")
out <- file.path(paper, "replication/own_account_output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
cols <- c("anio", "edad", "sector", "subrama_det", "tamano_empresa",
  "educacion", "posicion_ocupacional", "posicion_ocupacional_label", "mujer", "formal",
  "fex", "horas", "ingreso_hora_real", "log_ingreso_hora_real")
d <- read_dta(input, col_select = all_of(cols)) %>% filter(anio == 2025)
d <- harmonize_occupation(d)
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
# Match the descriptive-table sample, not the regression's singleton-cell exclusions.
d <- d %>% filter(!is.na(log_ingreso_hora_real), !is.na(ingreso_hora_real),
  tamano_empresa %in% sizes, !is.na(mujer), !is.na(educacion), !is.na(formal),
  !is.na(sector), is.finite(fex), fex > 0) %>%
  mutate(own_account = occupation_raw_code == 4L,
    higher_education = educacion == "Superior o universitaria",
    group = if_else(formal == 1, "Formal", "Informal"),
    size_group = case_when(tamano_empresa == "Solo" ~ "Solo",
      tamano_empresa == "101+" ~ "101+", TRUE ~ "2-100"))
stopifnot(all(d$own_account == (as.character(d$posicion_ocupacional_label) == "Trabajador por cuenta propia")))
write_csv <- function(x, name) write.csv(x, file.path(out, paste0(name, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8")
composition <- d %>% group_by(group, size_group) %>% summarise(
  observations = n(), own_account_observations = sum(own_account),
  own_account_pct = 100 * weighted.mean(own_account, fex), .groups = "drop")
formal_composition <- composition %>% filter(group == "Formal")
expected <- c("Solo" = 82.1, "2-100" = 7.7, "101+" = 9.6)
stopifnot(all(abs(formal_composition$own_account_pct - expected[formal_composition$size_group]) < .05))
write_csv(composition, "size_composition_2025")
target <- d %>% filter(own_account, tamano_empresa == "101+")
profile <- function(x) x %>% group_by(group) %>% summarise(observations = n(),
  mean_age = weighted.mean(edad, fex, na.rm = TRUE),
  women_pct = 100 * weighted.mean(mujer == 1, fex),
  higher_education_pct = 100 * weighted.mean(higher_education, fex),
  mean_hourly_income_2025_cop = weighted.mean(ingreso_hora_real, fex),
  mean_weekly_hours = weighted.mean(horas, fex, na.rm = TRUE), .groups = "drop")
profiles <- bind_rows(profile(target), profile(mutate(target, group = "All")))
write_csv(profiles, "profiles_2025")
formal_share <- 100 * weighted.mean(target$formal == 1, target$fex)
write_csv(data.frame(measure = c("2025_descriptive_observations", "own_account_101_plus_observations",
  "formal_share_of_own_account_101_plus_pct"), value = c(nrow(d), nrow(target), formal_share)), "summary_2025")

composition_by <- function(x, variable) {
  x %>% mutate(category = as.character(.data[[variable]]),
    category = if_else(is.na(category) | trimws(category) == "", "Not reported", category)) %>%
    group_by(group, category) %>% summarise(observations = n(), weight = sum(fex), .groups = "drop") %>%
    mutate(category = if_else(observations < 20, "Other categories (each fewer than 20 observations)", category)) %>%
    group_by(group, category) %>% summarise(observations = sum(observations), weight = sum(weight), .groups = "drop") %>%
    group_by(group) %>% mutate(share_pct = 100 * weight / sum(weight)) %>%
    ungroup() %>% select(-weight) %>% arrange(group, desc(share_pct))
}
for (variable in c("sector", "subrama_det", "educacion")) {
  tab <- composition_by(target, variable)
  stopifnot(all(abs(tapply(tab$share_pct, tab$group, sum) - 100) < 1e-8))
  write_csv(tab, paste0(variable, "_2025"))
}
write_csv(data.frame(check = c("Occupation code 4 agrees with own-account label",
  "All three formal own-account shares reproduce Table 4 to one decimal",
  "Within-group composition shares sum to 100", "No individual records exported"), passed = TRUE), "checks")
print(composition)
print(profiles)
print(composition_by(target, "sector"), n = 40)
message("Formal share among own-account workers in 101+: ", round(formal_share, 2), "%")
message("No contractor indicator is retained in the paper input. Activity codes do not identify contract status.")
