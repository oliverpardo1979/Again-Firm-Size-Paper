args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
cjc <- file.path(dirname(paper), "CJC-Monitor")
.libPaths(c(file.path(cjc, ".Rlib"), .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr)})
source(file.path(paper, "replication/harmonize_occupation.R"))
# Historical input. Use primary_worker_profiles.py for the corrected public-data sample.
input <- if (length(args)) args[1] else file.path(cjc, "Datos/Processed/Paper-GEIH_base_modelo_personas_2008_2025.dta")
out <- file.path(paper, "replication/formal_solo_output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
cols <- c("anio", "formal", "tamano_empresa", "educacion", "sector", "rama4d_clase",
  "posicion_ocupacional", "posicion_ocupacional_label", "mujer", "fex",
  "ingreso_hora_real", "log_ingreso_hora_real")
d <- harmonize_occupation(read_dta(input, col_select = all_of(cols))) %>%
  filter(anio == 2025, formal == 1, tamano_empresa == "Solo",
    is.finite(log_ingreso_hora_real), is.finite(ingreso_hora_real),
    !is.na(educacion), !is.na(sector), !is.na(mujer), is.finite(fex), fex > 0) %>%
  mutate(higher_education = educacion == "Superior o universitaria",
    own_account = occupation_raw_code == 4L)
stopifnot(all(d$own_account == (d$posicion_ocupacional_label == "Trabajador por cuenta propia")))
profiles <- d %>% group_by(higher_education) %>% summarise(
  observations = n(), weight = sum(fex),
  own_account_pct = 100 * weighted.mean(own_account, fex),
  mean_hourly_income_2025_cop = weighted.mean(ingreso_hora_real, fex), .groups = "drop") %>%
  mutate(share_of_formal_solo_pct = 100 * weight / sum(weight)) %>% select(-weight)
higher <- d %>% filter(higher_education)
activities <- data.frame(code = c("6910", "6920"),
  activity = c("Legal services", "Accounting, auditing and tax consultancy"))
activities$observations <- vapply(activities$code,
  function(code) sum(higher$rama4d_clase == code, na.rm = TRUE), integer(1))
activities$share_of_higher_education_formal_solo_pct <- vapply(activities$code,
  function(code) 100 * sum(higher$fex[!is.na(higher$rama4d_clase) & higher$rama4d_clase == code]) /
    sum(higher$fex), numeric(1))
stopifnot(all(activities$observations >= 20))
hi <- profiles[profiles$higher_education, ]
lo <- profiles[!profiles$higher_education, ]
checks <- data.frame(check = c("Higher-education share rounds to 50.9 percent",
  "Own-account share within higher education rounds to 95.5 percent",
  "Higher-education hourly mean rounds to 21826 pesos",
  "Other-education hourly mean rounds to 9950 pesos", "Shares sum to 100 percent"),
  passed = c(round(hi$share_of_formal_solo_pct, 1) == 50.9,
    round(hi$own_account_pct, 1) == 95.5,
    round(hi$mean_hourly_income_2025_cop) == 21826,
    round(lo$mean_hourly_income_2025_cop) == 9950,
    abs(sum(profiles$share_of_formal_solo_pct) - 100) < 1e-8))
stopifnot(all(checks$passed))
write.csv(profiles, file.path(out, "education_profiles_2025.csv"), row.names = FALSE)
write.csv(activities, file.path(out, "selected_activities_2025.csv"), row.names = FALSE)
write.csv(checks, file.path(out, "checks.csv"), row.names = FALSE)
print(profiles)
print(activities)
message("Only aggregates exported. No observations recoded or removed from the paper sample.")
