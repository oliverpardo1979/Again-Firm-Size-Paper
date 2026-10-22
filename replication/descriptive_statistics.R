if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
local_r_lib <- file.path(dirname(paper), "CJC-Monitor/.Rlib")
if (dir.exists(local_r_lib)) {
  .libPaths(c(local_r_lib, .libPaths()))
}

staging <- file.path(paper, "build/descriptive_refresh")
dir.create(staging, recursive = TRUE, showWarnings = FALSE)
setwd(staging)
geih_personas_data_path <- function() file.path(paper, "data/GEIH_primary_income_2008_2025.dta")

library(haven)
library(dplyr)
library(ggplot2)
library(scales)

options(scipen = 999)

save_figure_versions <- function(base_name, plot_en, plot_es, width, height, dpi = 300) {
  dir.create("Paper/figures", recursive = TRUE, showWarnings = FALSE)

  ggsave(
    filename = file.path("Paper/figures", paste0(base_name, "_en.png")),
    plot = plot_en,
    width = width,
    height = height,
    dpi = dpi
  )

  ggsave(
    filename = file.path("Paper/figures", paste0(base_name, "_es.png")),
    plot = plot_es,
    width = width,
    height = height,
    dpi = dpi
  )

  ggsave(
    filename = file.path("Paper/figures", paste0(base_name, ".png")),
    plot = plot_en,
    width = width,
    height = height,
    dpi = dpi
  )
}

size_levels <- c(
  "Solo",
  "2-3",
  "4-5",
  "6-10",
  "11-19",
  "20-30",
  "31-50",
  "51-100",
  "101+"
)

weighted_mean <- function(x, w) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  if (!any(ok)) {
    return(NA_real_)
  }
  weighted.mean(x[ok], w[ok])
}

weighted_sd <- function(x, w) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  if (!any(ok)) {
    return(NA_real_)
  }
  mu <- weighted.mean(x[ok], w[ok])
  sqrt(weighted.mean((x[ok] - mu)^2, w[ok]))
}

weighted_quantile <- function(x, w, probs) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  if (!any(ok)) {
    return(rep(NA_real_, length(probs)))
  }

  x <- x[ok]
  w <- w[ok]
  ord <- order(x)
  x <- x[ord]
  w <- w[ord]
  cw <- cumsum(w) / sum(w)

  vapply(
    probs,
    function(p) x[which(cw >= p)[1]],
    numeric(1)
  )
}

format_count <- function(x) {
  format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE)
}

format_number <- function(x, digits = 1) {
  format(round(x, digits), big.mark = ",", scientific = FALSE, trim = TRUE)
}

format_pct <- function(x, digits = 1) {
  paste0(format_number(100 * x, digits), "\\%")
}

format_pct_value <- function(x, digits = 1) {
  paste0(format_number(x, digits), "\\%")
}

format_money <- function(x) {
  format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE)
}

write_latex_table <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path)
}

geih <- read_dta(geih_personas_data_path()) %>%
  mutate(
    anio = as.integer(anio),
    tamano_empresa = as.character(tamano_empresa),
    sector = as.character(sector),
    educacion = as.character(educacion),
    formalidad = as.character(formalidad)
  )

valid_income_sample <- geih %>%
  filter(
    !is.na(ingreso_hora_real),
    !is.na(fex),
    fex > 0
  )

geih_model <- geih %>%
  filter(
    !is.na(log_ingreso_hora_real),
    !is.na(ingreso_hora_real),
    !is.na(tamano_empresa),
    !is.na(mujer),
    !is.na(educacion),
    !is.na(formal),
    !is.na(sector),
    !is.na(anio),
    !is.na(fex),
    fex > 0
  ) %>%
  mutate(
    tamano_empresa = factor(tamano_empresa, levels = size_levels),
    female_worker = as.numeric(mujer == 1),
    formal_worker = as.numeric(formal == 1),
    higher_education = as.numeric(educacion == "Superior o universitaria")
  ) %>%
  filter(!is.na(tamano_empresa))

dir.create("Paper/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("Paper/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("Paper/sections", recursive = TRUE, showWarnings = FALSE)

years <- sort(unique(geih_model$anio))
year_span <- paste0(
  min(years),
  "--",
  max(years),
  " (",
  length(years),
  " survey years; 2020 absent)"
)

sample_summary <- data.frame(
  Statistic = c(
    "Harmonized worker-year file",
    "Valid real hourly income and positive weights",
    "Regression/descriptive sample",
    "Years covered",
    "Firm-size categories"
  ),
  Value = c(
    format_count(nrow(geih)),
    format_count(nrow(valid_income_sample)),
    format_count(nrow(geih_model)),
    year_span,
    paste(size_levels, collapse = ", ")
  ),
  stringsAsFactors = FALSE
)

sample_rows <- paste0(
  "    ",
  sample_summary$Statistic,
  " & ",
  sample_summary$Value,
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Sample construction and coverage}",
    "  \\label{tab:sample-construction}",
    "  \\small",
    "  \\begin{tabular}{lp{0.58\\textwidth}}",
    "    \\toprule",
    "    Statistic & Value \\\\",
    "    \\midrule",
    sample_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_sample_table.tex"
)

employment_size_year <- geih_model %>%
  group_by(anio, tamano_empresa) %>%
  summarise(
    observations = n(),
    expanded_employment = sum(fex, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(anio) %>%
  mutate(employment_share = expanded_employment / sum(expanded_employment, na.rm = TRUE)) %>%
  ungroup()

share_first <- employment_size_year %>%
  filter(anio == min(years)) %>%
  select(tamano_empresa, share_first = employment_share)

share_last <- employment_size_year %>%
  filter(anio == max(years)) %>%
  select(tamano_empresa, share_last = employment_share)

employment_size <- geih_model %>%
  group_by(tamano_empresa) %>%
  summarise(
    observations = n(),
    expanded_worker_years = sum(fex, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(pooled_share = expanded_worker_years / sum(expanded_worker_years, na.rm = TRUE)) %>%
  left_join(share_first, by = "tamano_empresa") %>%
  left_join(share_last, by = "tamano_empresa") %>%
  arrange(tamano_empresa)

write.csv(
  employment_size,
  "Paper/tables/descriptive_employment_by_size.csv",
  row.names = FALSE
)

employment_rows <- paste0(
  "    ",
  employment_size$tamano_empresa,
  " & ",
  format_count(employment_size$observations),
  " & ",
  format_number(employment_size$expanded_worker_years / 1e6, 1),
  " & ",
  format_pct(employment_size$pooled_share),
  " & ",
  format_pct(employment_size$share_first),
  " & ",
  format_pct(employment_size$share_last),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Employment distribution by firm size}",
    "  \\label{tab:descriptive-employment-size}",
    "  \\small",
    "  \\begin{tabular}{lrrrrr}",
    "    \\toprule",
    "    Firm size & Observations & Worker-years (m) & Pooled share & 2008 share & 2025 share \\\\",
    "    \\midrule",
    employment_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Worker-years and employment shares use GEIH expansion weights. The sample matches the baseline regression sample.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_employment_size_table.tex"
)

income_size <- geih_model %>%
  group_by(tamano_empresa) %>%
  summarise(
    mean_income = weighted_mean(ingreso_hora_real, fex),
    p25_income = weighted_quantile(ingreso_hora_real, fex, 0.25),
    median_income = weighted_quantile(ingreso_hora_real, fex, 0.50),
    p75_income = weighted_quantile(ingreso_hora_real, fex, 0.75),
    sd_income = weighted_sd(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  mutate(
    raw_premium = 100 * (mean_income / mean_income[tamano_empresa == "Solo"] - 1)
  ) %>%
  arrange(tamano_empresa)

write.csv(
  income_size,
  "Paper/tables/descriptive_income_by_size.csv",
  row.names = FALSE
)

income_rows <- paste0(
  "    ",
  income_size$tamano_empresa,
  " & ",
  format_money(income_size$mean_income),
  " & ",
  format_money(income_size$p25_income),
  " & ",
  format_money(income_size$median_income),
  " & ",
  format_money(income_size$p75_income),
  " & ",
  format_money(income_size$sd_income),
  " & ",
  format_pct_value(income_size$raw_premium),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Real hourly labor income by firm size, pooled years}",
    "  \\label{tab:descriptive-income-size}",
    "  \\small",
    "  \\begin{tabular}{lrrrrrr}",
    "    \\toprule",
    "    Firm size & Mean & P25 & Median & P75 & S.D. & Raw premium \\\\",
    "    \\midrule",
    income_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Incomes are pooled over 2008--2019 and 2021--2025 and expressed as real hourly labor income in constant 2025 pesos. All statistics are weighted by GEIH expansion weights. The raw premium is the percent difference in the weighted mean relative to solo workers.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_income_size_table.tex"
)

income_size_2025 <- geih_model %>%
  filter(anio == 2025) %>%
  group_by(tamano_empresa) %>%
  summarise(
    mean_income = weighted_mean(ingreso_hora_real, fex),
    p25_income = weighted_quantile(ingreso_hora_real, fex, 0.25),
    median_income = weighted_quantile(ingreso_hora_real, fex, 0.50),
    p75_income = weighted_quantile(ingreso_hora_real, fex, 0.75),
    sd_income = weighted_sd(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  mutate(
    raw_premium = 100 * (mean_income / mean_income[tamano_empresa == "Solo"] - 1)
  ) %>%
  arrange(tamano_empresa)

write.csv(
  income_size_2025,
  "Paper/tables/descriptive_income_by_size_2025.csv",
  row.names = FALSE
)

income_rows_2025 <- paste0(
  "    ",
  income_size_2025$tamano_empresa,
  " & ",
  format_money(income_size_2025$mean_income),
  " & ",
  format_money(income_size_2025$p25_income),
  " & ",
  format_money(income_size_2025$median_income),
  " & ",
  format_money(income_size_2025$p75_income),
  " & ",
  format_money(income_size_2025$sd_income),
  " & ",
  format_pct_value(income_size_2025$raw_premium),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Real hourly labor income by firm size, 2025}",
    "  \\label{tab:descriptive-income-size-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrrrr}",
    "    \\toprule",
    "    Firm size & Mean & P25 & Median & P75 & S.D. & Raw premium \\\\",
    "    \\midrule",
    income_rows_2025,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Incomes use only 2025 observations and are expressed as real hourly labor income in constant 2025 pesos. All statistics are weighted by GEIH expansion weights. The raw premium is the percent difference in the weighted mean relative to solo workers in 2025.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_income_size_2025_table.tex"
)

income_comparison <- income_size %>%
  select(
    tamano_empresa,
    pooled_mean_income = mean_income,
    pooled_raw_premium = raw_premium
  ) %>%
  left_join(
    income_size_2025 %>%
      select(
        tamano_empresa,
        income_2025 = mean_income,
        raw_premium_2025 = raw_premium
      ),
    by = "tamano_empresa"
  )

write.csv(
  income_comparison,
  "Paper/tables/descriptive_income_by_size_comparison.csv",
  row.names = FALSE
)

income_comparison_rows <- paste0(
  "    ",
  income_comparison$tamano_empresa,
  " & ",
  format_money(income_comparison$pooled_mean_income),
  " & ",
  format_money(income_comparison$income_2025),
  " & ",
  format_pct_value(income_comparison$pooled_raw_premium),
  " & ",
  format_pct_value(income_comparison$raw_premium_2025),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Real hourly labor income by firm size: pooled sample and 2025}",
    "  \\label{tab:descriptive-income-size-comparison}",
    "  \\small",
    "  \\begin{tabular}{lrrrr}",
    "    \\toprule",
    "    Firm size & Pooled mean & 2025 mean & Pooled premium & 2025 premium \\\\",
    "    \\midrule",
    income_comparison_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Pooled statistics use 2008--2019 and 2021--2025. All income values are real hourly labor income in constant 2025 pesos and use GEIH expansion weights. Premiums are percent differences in weighted means relative to solo workers within each column.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_income_size_comparison_table.tex"
)

summarise_wage_groups <- function(data, statistic = c("mean", "median")) {
  statistic <- match.arg(statistic)

  stat_fun <- switch(
    statistic,
    mean = weighted_mean,
    median = function(x, w) weighted_quantile(x, w, 0.50)
  )

  summarise_one <- function(df, firm_size_label) {
    data.frame(
      firm_size = firm_size_label,
      all = stat_fun(df$ingreso_hora_real, df$fex),
      men = stat_fun(df$ingreso_hora_real[df$female_worker == 0], df$fex[df$female_worker == 0]),
      women = stat_fun(df$ingreso_hora_real[df$female_worker == 1], df$fex[df$female_worker == 1]),
      formal = stat_fun(df$ingreso_hora_real[df$formal_worker == 1], df$fex[df$formal_worker == 1]),
      informal = stat_fun(df$ingreso_hora_real[df$formal_worker == 0], df$fex[df$formal_worker == 0]),
      stringsAsFactors = FALSE
    )
  }

  by_size <- lapply(
    size_levels,
    function(size) summarise_one(
      data %>% filter(tamano_empresa == size),
      size
    )
  )

  bind_rows(
    summarise_one(data, "All firm sizes"),
    bind_rows(by_size)
  )
}

format_wage_group_rows <- function(data) {
  paste0(
    "    ",
    data$firm_size,
    " & ",
    format_money(data$all),
    " & ",
    format_money(data$men),
    " & ",
    format_money(data$women),
    " & ",
    format_money(data$formal),
    " & ",
    format_money(data$informal),
    " \\\\"
  )
}

wage_groups_2008 <- geih_model %>%
  filter(anio == 2008) %>%
  summarise_wage_groups(statistic = "mean") %>%
  mutate(year = 2008)

wage_groups_2025 <- geih_model %>%
  filter(anio == 2025) %>%
  summarise_wage_groups(statistic = "mean") %>%
  mutate(year = 2025)

wage_groups_mean_2008_2025 <- bind_rows(wage_groups_2008, wage_groups_2025) %>%
  select(year, firm_size, all, men, women, formal, informal)

write.csv(
  wage_groups_mean_2008_2025,
  "Paper/tables/descriptive_wage_groups_mean_2008_2025.csv",
  row.names = FALSE
)

core_size_2008_2025 <- employment_size %>%
  transmute(
    firm_size = as.character(tamano_empresa),
    employment_share_2008 = share_first,
    employment_share_2025 = share_last
  ) %>%
  left_join(
    wage_groups_2008 %>%
      filter(firm_size != "All firm sizes") %>%
      select(firm_size, mean_income_2008 = all),
    by = "firm_size"
  ) %>%
  left_join(
    wage_groups_2025 %>%
      filter(firm_size != "All firm sizes") %>%
      select(firm_size, mean_income_2025 = all),
    by = "firm_size"
  ) %>%
  bind_rows(
    data.frame(
      firm_size = "All workers",
      employment_share_2008 = 1,
      employment_share_2025 = 1,
      mean_income_2008 = wage_groups_2008$all[wage_groups_2008$firm_size == "All firm sizes"],
      mean_income_2025 = wage_groups_2025$all[wage_groups_2025$firm_size == "All firm sizes"],
      stringsAsFactors = FALSE
    )
  ) %>%
  mutate(
    wage_ratio_2008 = mean_income_2008 / mean_income_2008[firm_size == "Solo"],
    wage_ratio_2025 = mean_income_2025 / mean_income_2025[firm_size == "Solo"],
    annualized_change = 100 * ((mean_income_2025 / mean_income_2008)^(1 / (2025 - 2008)) - 1)
  )

write.csv(
  core_size_2008_2025,
  "Paper/tables/descriptive_core_size_2008_2025.csv",
  row.names = FALSE
)

core_size_row_prefix <- if_else(
  core_size_2008_2025$firm_size == "All workers",
  "    \\addlinespace\n    ",
  "    "
)

core_size_rows <- paste0(
  core_size_row_prefix,
  core_size_2008_2025$firm_size,
  " & ",
  format_pct(core_size_2008_2025$employment_share_2008),
  " & ",
  format_pct(core_size_2008_2025$employment_share_2025),
  " & ",
  format_money(core_size_2008_2025$mean_income_2008),
  " & ",
  format_money(core_size_2008_2025$mean_income_2025),
  " & ",
  format_number(core_size_2008_2025$wage_ratio_2008, 1),
  " & ",
  format_number(core_size_2008_2025$wage_ratio_2025, 1),
  " & ",
  format_pct_value(core_size_2008_2025$annualized_change),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Employment shares, mean real hourly income, and wage growth by firm size, 2008 and 2025}",
    "  \\label{tab:descriptive-core-size-2008-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrrrrr}",
    "    \\toprule",
    "    & \\multicolumn{2}{c}{Employment share} & \\multicolumn{2}{c}{Mean hourly income} & \\multicolumn{2}{c}{Wage ratio to solo} & \\multicolumn{1}{c}{Wage growth} \\\\",
    "    \\cmidrule(lr){2-3} \\cmidrule(lr){4-5} \\cmidrule(lr){6-7} \\cmidrule(lr){8-8}",
    "    Firm size & 2008 & 2025 & 2008 & 2025 & 2008 & 2025 & Annualized \\\\",
    "    \\midrule",
    core_size_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Employment shares and wages use GEIH expansion weights. Mean hourly income is expressed in constant 2025 pesos. Wage ratios divide each firm-size mean by the solo-worker mean in the same year. Annualized change is the compound annual change in mean hourly income between 2008 and 2025.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_core_size_2008_2025_table.tex"
)

wage_groups_2008_rows <- format_wage_group_rows(wage_groups_2008)
wage_groups_2025_rows <- format_wage_group_rows(wage_groups_2025)

write_latex_table(
  c(
    "\\begin{table}[!htbp]",
    "  \\centering",
    "  \\caption{Mean real hourly labor income by firm size and worker group, 2008 and 2025}",
    "  \\label{tab:descriptive-wage-groups-mean-2008-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrrr}",
    "    \\toprule",
    "    Firm size & All & Men & Women & Formal & Informal \\\\",
    "    \\midrule",
    "    \\multicolumn{6}{l}{\\textit{Panel A: 2008}} \\\\",
    wage_groups_2008_rows,
    "    \\addlinespace",
    "    \\multicolumn{6}{l}{\\textit{Panel B: 2025}} \\\\",
    wage_groups_2025_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Values are weighted mean real hourly labor income in constant 2025 pesos. The first row pools all firm-size categories. Men and women are defined from the worker's reported sex; formal and informal are defined using the baseline formality indicator.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_wage_groups_mean_2008_2025_table.tex"
)

wage_growth_2008_2025 <- wage_groups_2008 %>%
  select(firm_size, mean_2008 = all) %>%
  left_join(
    wage_groups_2025 %>%
      select(firm_size, mean_2025 = all),
    by = "firm_size"
  ) %>%
  mutate(change_percent = 100 * (mean_2025 / mean_2008 - 1))

write.csv(
  wage_growth_2008_2025,
  "Paper/tables/descriptive_wage_growth_2008_2025.csv",
  row.names = FALSE
)

wage_growth_rows <- paste0(
  "    ",
  wage_growth_2008_2025$firm_size,
  " & ",
  format_money(wage_growth_2008_2025$mean_2008),
  " & ",
  format_money(wage_growth_2008_2025$mean_2025),
  " & ",
  format_pct_value(wage_growth_2008_2025$change_percent),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[!htbp]",
    "  \\centering",
    "  \\caption{Growth in mean real hourly labor income by firm size, 2008--2025}",
    "  \\label{tab:descriptive-wage-growth-2008-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrr}",
    "    \\toprule",
    "    Firm size & 2008 mean & 2025 mean & Change \\\\",
    "    \\midrule",
    wage_growth_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Values are weighted mean real hourly labor income in constant 2025 pesos. Change is the percent change in the weighted mean between 2008 and 2025.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_wage_growth_2008_2025_table.tex"
)

wage_medians_2008 <- geih_model %>%
  filter(anio == 2008) %>%
  summarise_wage_groups(statistic = "median") %>%
  mutate(year = 2008)

wage_medians_2025 <- geih_model %>%
  filter(anio == 2025) %>%
  summarise_wage_groups(statistic = "median") %>%
  mutate(year = 2025)

wage_groups_median_2008_2025 <- bind_rows(wage_medians_2008, wage_medians_2025) %>%
  select(year, firm_size, all, men, women, formal, informal)

write.csv(
  wage_groups_median_2008_2025,
  "Paper/tables/descriptive_wage_groups_median_2008_2025.csv",
  row.names = FALSE
)

wage_medians_2008_rows <- format_wage_group_rows(wage_medians_2008)
wage_medians_2025_rows <- format_wage_group_rows(wage_medians_2025)

write_latex_table(
  c(
    "\\begin{table}[!htbp]",
    "  \\centering",
    "  \\caption{Median real hourly labor income by firm size and worker group, 2008 and 2025}",
    "  \\label{tab:descriptive-wage-groups-median-2008-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrrr}",
    "    \\toprule",
    "    Firm size & All & Men & Women & Formal & Informal \\\\",
    "    \\midrule",
    "    \\multicolumn{6}{l}{\\textit{Panel A: 2008}} \\\\",
    wage_medians_2008_rows,
    "    \\addlinespace",
    "    \\multicolumn{6}{l}{\\textit{Panel B: 2025}} \\\\",
    wage_medians_2025_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Values are weighted median real hourly labor income in constant 2025 pesos. The first row pools all firm-size categories. Men and women are defined from the worker's reported sex; formal and informal are defined using the baseline formality indicator.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_wage_groups_median_2008_2025_table.tex"
)

worker_balance <- geih_model %>%
  group_by(tamano_empresa) %>%
  summarise(
    women = weighted_mean(female_worker, fex),
    formal = weighted_mean(formal_worker, fex),
    higher_education = weighted_mean(higher_education, fex),
    mean_age = weighted_mean(edad, fex),
    .groups = "drop"
  ) %>%
  arrange(tamano_empresa)

write.csv(
  worker_balance,
  "Paper/tables/descriptive_worker_characteristics_by_size.csv",
  row.names = FALSE
)

balance_rows <- paste0(
  "    ",
  worker_balance$tamano_empresa,
  " & ",
  format_pct(worker_balance$women),
  " & ",
  format_pct(worker_balance$formal),
  " & ",
  format_pct(worker_balance$higher_education),
  " & ",
  format_number(worker_balance$mean_age, 1),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Worker characteristics by firm size, pooled years}",
    "  \\label{tab:descriptive-worker-characteristics}",
    "  \\small",
    "  \\begin{tabular}{lrrrr}",
    "    \\toprule",
    "    Firm size & Women & Formal & Higher education & Mean age \\\\",
    "    \\midrule",
    balance_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Statistics are pooled over 2008--2019 and 2021--2025 and weighted by GEIH expansion weights. Higher education corresponds to workers classified as superior or university educated.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_worker_characteristics_table.tex"
)

worker_balance_2025 <- geih_model %>%
  filter(anio == 2025) %>%
  group_by(tamano_empresa) %>%
  summarise(
    women = weighted_mean(female_worker, fex),
    formal = weighted_mean(formal_worker, fex),
    higher_education = weighted_mean(higher_education, fex),
    mean_age = weighted_mean(edad, fex),
    .groups = "drop"
  ) %>%
  arrange(tamano_empresa)

write.csv(
  worker_balance_2025,
  "Paper/tables/descriptive_worker_characteristics_by_size_2025.csv",
  row.names = FALSE
)

balance_rows_2025 <- paste0(
  "    ",
  worker_balance_2025$tamano_empresa,
  " & ",
  format_pct(worker_balance_2025$women),
  " & ",
  format_pct(worker_balance_2025$formal),
  " & ",
  format_pct(worker_balance_2025$higher_education),
  " & ",
  format_number(worker_balance_2025$mean_age, 1),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Worker characteristics by firm size, 2025}",
    "  \\label{tab:descriptive-worker-characteristics-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrr}",
    "    \\toprule",
    "    Firm size & Women & Formal & Higher education & Mean age \\\\",
    "    \\midrule",
    balance_rows_2025,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Statistics use only 2025 observations and are weighted by GEIH expansion weights. Higher education corresponds to workers classified as superior or university educated.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_worker_characteristics_2025_table.tex"
)

worker_balance_comparison <- worker_balance %>%
  select(
    tamano_empresa,
    women_pooled = women,
    formal_pooled = formal,
    higher_education_pooled = higher_education
  ) %>%
  left_join(
    worker_balance_2025 %>%
      select(
        tamano_empresa,
        women_2025 = women,
        formal_2025 = formal,
        higher_education_2025 = higher_education
      ),
    by = "tamano_empresa"
  )

write.csv(
  worker_balance_comparison,
  "Paper/tables/descriptive_worker_characteristics_by_size_comparison.csv",
  row.names = FALSE
)

worker_balance_comparison_rows <- paste0(
  "    ",
  worker_balance_comparison$tamano_empresa,
  " & ",
  format_pct(worker_balance_comparison$women_pooled),
  " & ",
  format_pct(worker_balance_comparison$women_2025),
  " & ",
  format_pct(worker_balance_comparison$formal_pooled),
  " & ",
  format_pct(worker_balance_comparison$formal_2025),
  " & ",
  format_pct(worker_balance_comparison$higher_education_pooled),
  " & ",
  format_pct(worker_balance_comparison$higher_education_2025),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Worker composition by firm size: pooled sample and 2025}",
    "  \\label{tab:descriptive-worker-characteristics-comparison}",
    "  \\small",
    "  \\begin{tabular}{lrrrrrr}",
    "    \\toprule",
    "    & \\multicolumn{2}{c}{Women} & \\multicolumn{2}{c}{Formal} & \\multicolumn{2}{c}{Higher education} \\\\",
    "    \\cmidrule(lr){2-3} \\cmidrule(lr){4-5} \\cmidrule(lr){6-7}",
    "    Firm size & Pooled & 2025 & Pooled & 2025 & Pooled & 2025 \\\\",
    "    \\midrule",
    worker_balance_comparison_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Pooled statistics use 2008--2019 and 2021--2025. All statistics use GEIH expansion weights. Higher education corresponds to workers classified as superior or university educated.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_worker_characteristics_comparison_table.tex"
)

formal_worker_profile_2025 <- geih_model %>%
  filter(anio == 2025, formal == 1) %>%
  mutate(
    formal_size_group = case_when(
      tamano_empresa == "Solo" ~ "Formal solo",
      tamano_empresa %in% c("2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100") ~ "Formal 2-100",
      tamano_empresa == "101+" ~ "Formal 101+",
      TRUE ~ NA_character_
    ),
    own_account = as.numeric(posicion_ocupacional_label == "Trabajador por cuenta propia"),
    domestic_worker = as.numeric(posicion_ocupacional_label == "Empleado doméstico"),
    professional_admin_sector = as.numeric(sector == "Inmobiliarias, profesionales y administrativas"),
    transport_sector = as.numeric(sector == "Transporte y almacenamiento"),
    commerce_sector = as.numeric(sector == "Comercio y reparación"),
    health_sector = as.numeric(sector == "Salud y asistencia social"),
    households_sector = as.numeric(sector == "Hogares como empleadores")
  ) %>%
  filter(!is.na(formal_size_group)) %>%
  group_by(formal_size_group) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_hourly_income = weighted_mean(ingreso_hora_real, fex),
    mean_age = weighted_mean(edad, fex),
    women = weighted_mean(female_worker, fex),
    higher_education = weighted_mean(higher_education, fex),
    own_account = weighted_mean(own_account, fex),
    domestic_worker = weighted_mean(domestic_worker, fex),
    professional_admin_sector = weighted_mean(professional_admin_sector, fex),
    transport_sector = weighted_mean(transport_sector, fex),
    commerce_sector = weighted_mean(commerce_sector, fex),
    health_sector = weighted_mean(health_sector, fex),
    households_sector = weighted_mean(households_sector, fex),
    .groups = "drop"
  ) %>%
  mutate(
    formal_size_group = factor(
      formal_size_group,
      levels = c("Formal solo", "Formal 2-100", "Formal 101+")
    ),
    share_formal_workers = workers / sum(workers)
  ) %>%
  arrange(formal_size_group)

write.csv(
  formal_worker_profile_2025,
  "Paper/tables/descriptive_formal_worker_profile_2025.csv",
  row.names = FALSE
)

formal_profile_value <- function(variable, formatter = format_pct) {
  formatter(formal_worker_profile_2025[[variable]])
}

formal_profile_rows <- c(
  paste0(
    "    Share of formal workers & ",
    paste(format_pct(formal_worker_profile_2025$share_formal_workers), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Mean real hourly income & ",
    paste(format_money(formal_worker_profile_2025$mean_hourly_income), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Mean age & ",
    paste(format_number(formal_worker_profile_2025$mean_age, 1), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Women & ",
    paste(formal_profile_value("women"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Higher education & ",
    paste(formal_profile_value("higher_education"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Own-account workers & ",
    paste(formal_profile_value("own_account"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Domestic workers & ",
    paste(formal_profile_value("domestic_worker"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Professional and administrative services & ",
    paste(formal_profile_value("professional_admin_sector"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Transport and storage & ",
    paste(formal_profile_value("transport_sector"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Commerce and repair & ",
    paste(formal_profile_value("commerce_sector"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Health and social assistance & ",
    paste(formal_profile_value("health_sector"), collapse = " & "),
    " \\\\"
  ),
  paste0(
    "    Households as employers & ",
    paste(formal_profile_value("households_sector"), collapse = " & "),
    " \\\\"
  )
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Profile of formal workers by firm-size group, 2025}",
    "  \\label{tab:formal-worker-profile-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrr}",
    "    \\toprule",
    "    Characteristic & Formal solo & Formal 2--100 & Formal 101+ \\\\",
    "    \\midrule",
    formal_profile_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Statistics use 2025 formal workers and GEIH expansion weights. The first row reports each column's share of all formal workers in the table. The 2--100 column pools all formal workers in firm-size categories from 2--3 through 51--100 workers. Higher education corresponds to workers classified as superior or university educated. Sector rows report the weighted share of each group located in the listed economic activity.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_formal_worker_profile_2025_table.tex"
)

theme_paper <- theme_classic(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom"
  )

employment_share_comparison <- bind_rows(
  employment_size %>%
    transmute(
      tamano_empresa,
      period = "2008",
      employment_share = share_first * 100
    ),
  employment_size %>%
    transmute(
      tamano_empresa,
      period = "2025",
      employment_share = share_last * 100
    )
) %>%
  mutate(period = factor(period, levels = c("2008", "2025")))

g_employment_share_comparison <- ggplot(
  employment_share_comparison,
  aes(
    x = tamano_empresa,
    y = employment_share,
    fill = period
  )
) +
  geom_col(position = position_dodge(width = 0.75), width = 0.68) +
  scale_fill_manual(
    values = c(
      "2008" = "darkgreen",
      "2025" = "darkblue"
    )
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Employment distribution by firm size",
    subtitle = "Weighted shares in 2008 and 2025",
    x = "Firm size",
    y = "Employment share",
    fill = NULL
  ) +
  theme_paper

g_employment_share_comparison_es <- g_employment_share_comparison +
  scale_fill_manual(
    values = c(
      "2008" = "darkgreen",
      "2025" = "darkblue"
    )
  ) +
  labs(
    title = "Distribuci\u00f3n del empleo por tama\u00f1o de empresa",
    subtitle = "Participaciones ponderadas en 2008 y 2025",
    x = "Tama\u00f1o de empresa",
    y = "Participaci\u00f3n en el empleo",
    fill = NULL
  )

save_figure_versions(
  base_name = "fig64",
  plot_en = g_employment_share_comparison,
  plot_es = g_employment_share_comparison_es,
  width = 10,
  height = 6,
  dpi = 300
)

income_mean_comparison <- bind_rows(
  wage_groups_2008 %>%
    filter(firm_size != "All firm sizes") %>%
    transmute(
      tamano_empresa = factor(firm_size, levels = size_levels),
      period = "2008",
      mean_income = all
    ),
  wage_groups_2025 %>%
    filter(firm_size != "All firm sizes") %>%
    transmute(
      tamano_empresa = factor(firm_size, levels = size_levels),
      period = "2025",
      mean_income = all
    )
) %>%
  mutate(period = factor(period, levels = c("2008", "2025"))) %>%
  left_join(
    employment_share_comparison %>%
      mutate(period = factor(as.character(period), levels = c("2008", "2025"))) %>%
      select(tamano_empresa, period, employment_share),
    by = c("tamano_empresa", "period")
  )

income_comparison_colors <- c(
  "2008" = "#D55E00",
  "2025" = "#0072B2"
)

income_comparison_fills <- c(
  "2008" = "white",
  "2025" = "#0072B2"
)

income_comparison_linetypes <- c(
  "2008" = "dashed",
  "2025" = "solid"
)

income_mean_label_data <- income_mean_comparison %>%
  filter(tamano_empresa == "101+")

g_income_mean_comparison <- ggplot(
  income_mean_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = period,
    linetype = period,
    group = period
  )
) +
  geom_line(linewidth = 0.95) +
  geom_point(
    aes(size = employment_share / 100, fill = period),
    shape = 21,
    stroke = 1.15,
    alpha = 0.9
  ) +
  geom_text(
    data = income_mean_label_data,
    aes(label = period),
    hjust = 0,
    nudge_x = 0.35,
    size = 3.5,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 9,
    labels = percent_format(accuracy = 1),
    name = "% of employment"
  ) +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.3))) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0.05, 0.1))
  ) +
  labs(
    title = "Mean real hourly income by firm size",
    subtitle = "2008 and 2025; bubble size is the employment share in each year",
    x = "Firm size",
    y = "Mean hourly income"
  ) +
  coord_cartesian(clip = "off") +
  theme_paper +
  theme(
    legend.box = "vertical",
    plot.margin = margin(5.5, 45, 5.5, 5.5)
  )

g_income_mean_comparison_es <- ggplot(
  income_mean_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = period,
    linetype = period,
    group = period
  )
) +
  geom_line(linewidth = 0.95) +
  geom_point(
    aes(size = employment_share / 100, fill = period),
    shape = 21,
    stroke = 1.15,
    alpha = 0.9
  ) +
  geom_text(
    data = income_mean_label_data,
    aes(label = period),
    hjust = 0,
    nudge_x = 0.35,
    size = 3.5,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 9,
    labels = percent_format(accuracy = 1),
    name = "% del empleo"
  ) +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.3))) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0.05, 0.1))
  ) +
  labs(
    title = "Ingreso laboral horario real promedio por tama\u00f1o de empresa",
    subtitle = "2008 y 2025; la burbuja representa la participaci\u00f3n en el empleo de cada a\u00f1o",
    x = "Tama\u00f1o de empresa",
    y = "Ingreso horario promedio"
  ) +
  coord_cartesian(clip = "off") +
  theme_paper +
  theme(
    legend.box = "vertical",
    plot.margin = margin(5.5, 45, 5.5, 5.5)
  )

save_figure_versions(
  base_name = "fig65",
  plot_en = g_income_mean_comparison,
  plot_es = g_income_mean_comparison_es,
  width = 11,
  height = 6.5,
  dpi = 300
)

formality_income_comparison <- geih_model %>%
  filter(
    anio %in% c(2008, 2025),
    formal %in% c(0, 1)
  ) %>%
  group_by(anio, formal_worker, tamano_empresa) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  group_by(anio, formal_worker) %>%
  mutate(worker_share = workers / sum(workers, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    year = factor(as.character(anio), levels = c("2008", "2025")),
    formality_status = factor(
      ifelse(formal_worker == 1, "Formal workers", "Informal workers"),
      levels = c("Formal workers", "Informal workers")
    ),
    formality_status_es = factor(
      ifelse(formal_worker == 1, "Trabajadores formales", "Trabajadores informales"),
      levels = c("Trabajadores formales", "Trabajadores informales")
    )
  )

write.csv(
  formality_income_comparison,
  "Paper/tables/descriptive_wage_by_formality_year_size.csv",
  row.names = FALSE
)

formality_income_label_data <- formality_income_comparison %>%
  filter(tamano_empresa == "101+")

g_formality_income_comparison <- ggplot(
  formality_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.95) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 1.15,
    alpha = 0.9
  ) +
  geom_text(
    data = formality_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.35,
    size = 3.2,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.3))) +
  facet_wrap(~ formality_status, ncol = 2) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 9,
    labels = percent_format(accuracy = 1),
    name = "% within formality-year"
  ) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0.05, 0.1))
  ) +
  labs(
    title = "Mean real hourly income by firm size and formality",
    subtitle = "2008 and 2025; bubble size is the worker share within each formality-year group",
    x = "Firm size",
    y = "Mean hourly income"
  ) +
  coord_cartesian(clip = "off") +
  theme_paper +
  theme(
    strip.text = element_text(face = "bold"),
    legend.box = "vertical",
    plot.margin = margin(5.5, 45, 5.5, 5.5)
  )

g_formality_income_comparison_es <- ggplot(
  formality_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.95) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 1.15,
    alpha = 0.9
  ) +
  geom_text(
    data = formality_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.35,
    size = 3.2,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.3))) +
  facet_wrap(~ formality_status_es, ncol = 2) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 9,
    labels = percent_format(accuracy = 1),
    name = "% dentro de formalidad-a\u00f1o"
  ) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0.05, 0.1))
  ) +
  labs(
    title = "Ingreso laboral horario real promedio por tama\u00f1o de empresa y formalidad",
    subtitle = "2008 y 2025; la burbuja representa el porcentaje de trabajadores dentro de cada grupo formalidad-a\u00f1o",
    x = "Tama\u00f1o de empresa",
    y = "Ingreso horario promedio"
  ) +
  coord_cartesian(clip = "off") +
  theme_paper +
  theme(
    strip.text = element_text(face = "bold"),
    legend.box = "vertical",
    plot.margin = margin(5.5, 45, 5.5, 5.5)
  )

save_figure_versions(
  base_name = "fig69",
  plot_en = g_formality_income_comparison,
  plot_es = g_formality_income_comparison_es,
  width = 11,
  height = 6.5,
  dpi = 300
)

sex_income_comparison <- geih_model %>%
  filter(
    anio %in% c(2008, 2025),
    mujer %in% c(0, 1)
  ) %>%
  group_by(anio, female_worker, tamano_empresa) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  group_by(anio, female_worker) %>%
  mutate(worker_share = workers / sum(workers, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    year = factor(as.character(anio), levels = c("2008", "2025")),
    sex = factor(
      ifelse(female_worker == 1, "Women", "Men"),
      levels = c("Men", "Women")
    ),
    sex_es = factor(
      ifelse(female_worker == 1, "Mujeres", "Hombres"),
      levels = c("Hombres", "Mujeres")
    )
  )

write.csv(
  sex_income_comparison,
  "Paper/tables/descriptive_wage_by_sex_year_size.csv",
  row.names = FALSE
)

sex_income_2025_table <- sex_income_comparison %>%
  filter(anio == 2025) %>%
  select(sex, tamano_empresa, mean_income) %>%
  tidyr::pivot_wider(names_from = sex, values_from = mean_income) %>%
  arrange(tamano_empresa) %>%
  mutate(
    men_ratio = Men / Men[tamano_empresa == "Solo"],
    women_ratio = Women / Women[tamano_empresa == "Solo"]
  )

write.csv(
  sex_income_2025_table,
  "Paper/tables/descriptive_wage_by_sex_size_2025.csv",
  row.names = FALSE
)

sex_income_2025_rows <- paste0(
  "    ",
  sex_income_2025_table$tamano_empresa,
  " & ",
  format_money(sex_income_2025_table$Men),
  " & ",
  format_money(sex_income_2025_table$Women),
  " & ",
  format_number(sex_income_2025_table$men_ratio, 1),
  " & ",
  format_number(sex_income_2025_table$women_ratio, 1),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Mean real hourly income by firm size and sex, 2025}",
    "  \\label{tab:descriptive-wage-sex-size-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrr}",
    "    \\toprule",
    "    & \\multicolumn{2}{c}{Mean hourly income} & \\multicolumn{2}{c}{Wage ratio to solo} \\\\",
    "    \\cmidrule(lr){2-3} \\cmidrule(lr){4-5}",
    "    Firm size & Men & Women & Men & Women \\\\",
    "    \\midrule",
    sex_income_2025_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Values are weighted mean real hourly labor income in constant 2025 pesos. Men and women are defined from the worker's reported sex. Wage ratios divide each firm-size mean by the solo-worker mean for the same sex.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_wage_sex_size_2025_table.tex"
)

sex_income_label_data <- sex_income_comparison %>%
  filter(tamano_empresa == "101+")

g_sex_income_comparison <- ggplot(
  sex_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.95) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 1.15,
    alpha = 0.9
  ) +
  geom_text(
    data = sex_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.35,
    size = 3.2,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.3))) +
  facet_wrap(~ sex, ncol = 2) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 9,
    labels = percent_format(accuracy = 1),
    name = "% within sex-year"
  ) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0.05, 0.1))
  ) +
  labs(
    title = "Mean real hourly income by firm size and sex",
    subtitle = "2008 and 2025; bubble size is the worker share within each sex-year group",
    x = "Firm size",
    y = "Mean hourly income"
  ) +
  coord_cartesian(clip = "off") +
  theme_paper +
  theme(
    strip.text = element_text(face = "bold"),
    legend.box = "vertical",
    plot.margin = margin(5.5, 45, 5.5, 5.5)
  )

g_sex_income_comparison_es <- ggplot(
  sex_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.95) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 1.15,
    alpha = 0.9
  ) +
  geom_text(
    data = sex_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.35,
    size = 3.2,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.3))) +
  facet_wrap(~ sex_es, ncol = 2) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 9,
    labels = percent_format(accuracy = 1),
    name = "% dentro de sexo-a\u00f1o"
  ) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0.05, 0.1))
  ) +
  labs(
    title = "Ingreso laboral horario real promedio por tama\u00f1o de empresa y sexo",
    subtitle = "2008 y 2025; la burbuja representa el porcentaje de trabajadores dentro de cada grupo sexo-a\u00f1o",
    x = "Tama\u00f1o de empresa",
    y = "Ingreso horario promedio"
  ) +
  coord_cartesian(clip = "off") +
  theme_paper +
  theme(
    strip.text = element_text(face = "bold"),
    legend.box = "vertical",
    plot.margin = margin(5.5, 45, 5.5, 5.5)
  )

save_figure_versions(
  base_name = "fig70",
  plot_en = g_sex_income_comparison,
  plot_es = g_sex_income_comparison_es,
  width = 11,
  height = 6.5,
  dpi = 300
)

education_income_comparison <- geih_model %>%
  filter(
    anio %in% c(2008, 2025),
    !is.na(educacion),
    !grepl("No sabe|no informa", as.character(educacion), ignore.case = TRUE)
  ) %>%
  mutate(
    education_chr = as.character(educacion),
    education_en = case_when(
      grepl("Ning|No educ|Pre", education_chr, ignore.case = TRUE) ~ "Preschool or less",
      grepl("primaria|Primary", education_chr, ignore.case = TRUE) ~ "Primary",
      grepl("secundaria|^Media$|secondary|upper", education_chr, ignore.case = TRUE) ~ "Secondary",
      grepl("Superior|universitaria|Higher", education_chr, ignore.case = TRUE) ~ "Higher education",
      TRUE ~ education_chr
    ),
    education_es = case_when(
      grepl("Ning|No educ|Pre", education_chr, ignore.case = TRUE) ~ "Preescolar o menos",
      grepl("primaria|Primary", education_chr, ignore.case = TRUE) ~ "Basica primaria",
      grepl("secundaria|^Media$|secondary|upper", education_chr, ignore.case = TRUE) ~ "Secundaria",
      grepl("Superior|universitaria|Higher", education_chr, ignore.case = TRUE) ~ "Superior o universitaria",
      TRUE ~ education_chr
    )
  ) %>%
  group_by(anio, education_en, education_es, tamano_empresa) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  group_by(anio, education_en, education_es) %>%
  mutate(worker_share = workers / sum(workers, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(year = factor(as.character(anio), levels = c("2008", "2025")))

education_order_en <- c(
  "Preschool or less",
  "Primary",
  "Secondary",
  "Higher education"
)

education_order_es <- c(
  "Preescolar o menos",
  "Basica primaria",
  "Secundaria",
  "Superior o universitaria"
)

education_income_comparison <- education_income_comparison %>%
  mutate(
    education_en = factor(
      education_en,
      levels = unique(c(education_order_en, sort(unique(as.character(education_en)))))
    ),
    education_es = factor(
      education_es,
      levels = unique(c(education_order_es, sort(unique(as.character(education_es)))))
    )
  )

write.csv(
  education_income_comparison,
  "Paper/tables/descriptive_wage_by_education_year_size.csv",
  row.names = FALSE
)

education_income_2025_table <- education_income_comparison %>%
  filter(anio == 2025, tamano_empresa %in% c("Solo", "101+")) %>%
  select(education_en, tamano_empresa, worker_share, mean_income) %>%
  tidyr::pivot_wider(
    names_from = tamano_empresa,
    values_from = c(worker_share, mean_income),
    names_glue = "{.value}_{tamano_empresa}"
  ) %>%
  mutate(wage_ratio = `mean_income_101+` / mean_income_Solo) %>%
  arrange(education_en)

write.csv(
  education_income_2025_table,
  "Paper/tables/descriptive_wage_by_education_endpoints_2025.csv",
  row.names = FALSE
)

education_income_2025_rows <- paste0(
  "    ",
  education_income_2025_table$education_en,
  " & ",
  format_pct(education_income_2025_table$worker_share_Solo),
  " & ",
  format_pct(education_income_2025_table$`worker_share_101+`),
  " & ",
  format_money(education_income_2025_table$mean_income_Solo),
  " & ",
  format_money(education_income_2025_table$`mean_income_101+`),
  " & ",
  format_number(education_income_2025_table$wage_ratio, 1),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Firm-size endpoints by education group, 2025}",
    "  \\label{tab:descriptive-education-endpoints-2025}",
    "  \\small",
    "  \\begin{tabular}{lrrrrr}",
    "    \\toprule",
    "    & \\multicolumn{2}{c}{Employment share} & \\multicolumn{2}{c}{Mean hourly income} & \\\\",
    "    \\cmidrule(lr){2-3} \\cmidrule(lr){4-5}",
    "    Education group & Solo & 101+ & Solo & 101+ & Wage ratio \\\\",
    "    \\midrule",
    education_income_2025_rows,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Statistics use 2025 observations and GEIH expansion weights. Employment shares are computed within education group. Mean hourly income is expressed in constant 2025 pesos. The wage ratio divides the 101+ mean by the solo-worker mean within education group.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_education_endpoints_2025_table.tex"
)

education_income_label_data <- education_income_comparison %>%
  filter(tamano_empresa == "101+")

theme_education_facet <- theme_classic(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
    axis.text.y = element_text(size = 8),
    strip.text = element_text(face = "bold", size = 9),
    legend.position = "bottom",
    legend.box = "vertical",
    panel.spacing = unit(0.65, "lines")
  )

g_education_income_comparison <- ggplot(
  education_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.8) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 1,
    alpha = 0.9
  ) +
  geom_text(
    data = education_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.28,
    size = 2.7,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.25, 1.1))) +
  facet_wrap(~ education_en, scales = "free_y", ncol = 2) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 7.5,
    labels = percent_format(accuracy = 1),
    name = "% within education-year"
  ) +
  scale_y_continuous(labels = comma) +
  labs(
    title = "Mean real hourly income by firm size and education",
    subtitle = "2008 and 2025; bubble size is the employment share within each education-year",
    x = "Firm size",
    y = "Mean hourly income"
  ) +
  coord_cartesian(clip = "off") +
  theme_education_facet +
  theme(plot.margin = margin(5.5, 45, 5.5, 5.5))

g_education_income_comparison_es <- ggplot(
  education_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.8) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 1,
    alpha = 0.9
  ) +
  geom_text(
    data = education_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.28,
    size = 2.7,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.25, 1.1))) +
  facet_wrap(~ education_es, scales = "free_y", ncol = 2) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 7.5,
    labels = percent_format(accuracy = 1),
    name = "% dentro de educacion-a\u00f1o"
  ) +
  scale_y_continuous(labels = comma) +
  labs(
    title = "Ingreso laboral horario real promedio por tama\u00f1o de empresa y educacion",
    subtitle = "2008 y 2025; la burbuja representa la participacion en el empleo dentro de cada educacion-a\u00f1o",
    x = "Tama\u00f1o de empresa",
    y = "Ingreso horario promedio"
  ) +
  coord_cartesian(clip = "off") +
  theme_education_facet +
  theme(plot.margin = margin(5.5, 45, 5.5, 5.5))

save_figure_versions(
  base_name = "fig72",
  plot_en = g_education_income_comparison,
  plot_es = g_education_income_comparison_es,
  width = 12,
  height = 7.5,
  dpi = 300
)

sector_income_comparison <- geih_model %>%
  filter(
    anio %in% c(2008, 2025),
    !is.na(sector)
  ) %>%
  group_by(anio, sector, tamano_empresa) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  group_by(anio, sector) %>%
  mutate(worker_share = workers / sum(workers, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    year = factor(as.character(anio), levels = c("2008", "2025")),
    sector_chr = as.character(sector),
    sector_label_en = case_when(
      grepl("Electricidad.*agua|saneamiento", sector_chr, ignore.case = TRUE) ~ "D/E - Utilities and water",
      grepl("Inmobiliarias.*profesionales|profesionales.*administrativas", sector_chr, ignore.case = TRUE) ~ "L/M/N - Business services",
      grepl("Artes.*otros servicios", sector_chr, ignore.case = TRUE) ~ "R/S - Arts and other services",
      grepl("^A$|^A\\s*-|Agro|Agric|pesca", sector_chr, ignore.case = TRUE) ~ "A - Agriculture",
      grepl("^B$|^B\\s*-|Minas|Mining", sector_chr, ignore.case = TRUE) ~ "B - Mining",
      grepl("^C$|^C\\s*-|Manufact", sector_chr, ignore.case = TRUE) ~ "C - Manufacturing",
      grepl("^D$|^D\\s*-|Electric", sector_chr, ignore.case = TRUE) ~ "D - Electricity and gas",
      grepl("^E$|^E\\s*-|Agua|Water", sector_chr, ignore.case = TRUE) ~ "E - Water and waste",
      grepl("^F$|^F\\s*-|Constru|Construction", sector_chr, ignore.case = TRUE) ~ "F - Construction",
      grepl("^G$|^G\\s*-|Comerc|Trade", sector_chr, ignore.case = TRUE) ~ "G - Commerce",
      grepl("^H$|^H\\s*-|Trans", sector_chr, ignore.case = TRUE) ~ "H - Transport",
      grepl("^I$|^I\\s*-|Aloj|comida|Accommodation|food", sector_chr, ignore.case = TRUE) ~ "I - Accommodation and food",
      grepl("^J$|^J\\s*-|Informaci|communication", sector_chr, ignore.case = TRUE) ~ "J - Information and communication",
      grepl("^K$|^K\\s*-|Finan", sector_chr, ignore.case = TRUE) ~ "K - Finance and insurance",
      grepl("^L$|^L\\s*-|Inmobili|Real estate", sector_chr, ignore.case = TRUE) ~ "L - Real estate",
      grepl("^M$|^M\\s*-|Profes", sector_chr, ignore.case = TRUE) ~ "M - Professional services",
      grepl("^N$|^N\\s*-|Servicios administrativos|Administrative", sector_chr, ignore.case = TRUE) ~ "N - Administrative services",
      grepl("^O$|^O\\s*-|Administraci|Public administration", sector_chr, ignore.case = TRUE) ~ "O - Public administration",
      grepl("^P$|^P\\s*-|Educ", sector_chr, ignore.case = TRUE) ~ "P - Education",
      grepl("^Q$|^Q\\s*-|Salud|Health", sector_chr, ignore.case = TRUE) ~ "Q - Health",
      grepl("^R$|^R\\s*-|Arte|recre", sector_chr, ignore.case = TRUE) ~ "R - Arts and recreation",
      grepl("^S$|^S\\s*-|Otros servicios|Other services", sector_chr, ignore.case = TRUE) ~ "S - Other services",
      grepl("^T$|^T\\s*-|Hogares|Household", sector_chr, ignore.case = TRUE) ~ "T - Household employers",
      grepl("^U$|^U\\s*-|extraterr", sector_chr, ignore.case = TRUE) ~ "U - Extraterritorial orgs.",
      TRUE ~ sector_chr
    ),
    sector_label_es = case_when(
      grepl("Electricidad.*agua|saneamiento", sector_chr, ignore.case = TRUE) ~ "D/E - Servicios publicos y agua",
      grepl("Inmobiliarias.*profesionales|profesionales.*administrativas", sector_chr, ignore.case = TRUE) ~ "L/M/N - Servicios empresariales",
      grepl("Artes.*otros servicios", sector_chr, ignore.case = TRUE) ~ "R/S - Arte y otros servicios",
      grepl("^A$|^A\\s*-|Agro|Agric|pesca", sector_chr, ignore.case = TRUE) ~ "A - Agro y pesca",
      grepl("^B$|^B\\s*-|Minas|Mining", sector_chr, ignore.case = TRUE) ~ "B - Minas",
      grepl("^C$|^C\\s*-|Manufact", sector_chr, ignore.case = TRUE) ~ "C - Manufactura",
      grepl("^D$|^D\\s*-|Electric", sector_chr, ignore.case = TRUE) ~ "D - Electricidad y gas",
      grepl("^E$|^E\\s*-|Agua|Water", sector_chr, ignore.case = TRUE) ~ "E - Agua y residuos",
      grepl("^F$|^F\\s*-|Constru|Construction", sector_chr, ignore.case = TRUE) ~ "F - Construccion",
      grepl("^G$|^G\\s*-|Comerc|Trade", sector_chr, ignore.case = TRUE) ~ "G - Comercio",
      grepl("^H$|^H\\s*-|Trans", sector_chr, ignore.case = TRUE) ~ "H - Transporte",
      grepl("^I$|^I\\s*-|Aloj|comida|Accommodation|food", sector_chr, ignore.case = TRUE) ~ "I - Alojamiento y comida",
      grepl("^J$|^J\\s*-|Informaci|communication", sector_chr, ignore.case = TRUE) ~ "J - Informacion y comunicaciones",
      grepl("^K$|^K\\s*-|Finan", sector_chr, ignore.case = TRUE) ~ "K - Finanzas y seguros",
      grepl("^L$|^L\\s*-|Inmobili|Real estate", sector_chr, ignore.case = TRUE) ~ "L - Inmobiliarias",
      grepl("^M$|^M\\s*-|Profes", sector_chr, ignore.case = TRUE) ~ "M - Profesionales y tecnicas",
      grepl("^N$|^N\\s*-|Servicios administrativos|Administrative", sector_chr, ignore.case = TRUE) ~ "N - Servicios administrativos",
      grepl("^O$|^O\\s*-|Administraci|Public administration", sector_chr, ignore.case = TRUE) ~ "O - Administracion publica",
      grepl("^P$|^P\\s*-|Educ", sector_chr, ignore.case = TRUE) ~ "P - Educacion",
      grepl("^Q$|^Q\\s*-|Salud|Health", sector_chr, ignore.case = TRUE) ~ "Q - Salud",
      grepl("^R$|^R\\s*-|Arte|recre", sector_chr, ignore.case = TRUE) ~ "R - Arte y recreacion",
      grepl("^S$|^S\\s*-|Otros servicios|Other services", sector_chr, ignore.case = TRUE) ~ "S - Otros servicios",
      grepl("^T$|^T\\s*-|Hogares|Household", sector_chr, ignore.case = TRUE) ~ "T - Hogares empleadores",
      grepl("^U$|^U\\s*-|extraterr", sector_chr, ignore.case = TRUE) ~ "U - Org. extraterritoriales",
      TRUE ~ sector_chr
    )
  )

sector_order_en <- c(
  "A - Agriculture",
  "B - Mining",
  "C - Manufacturing",
  "D/E - Utilities and water",
  "F - Construction",
  "G - Commerce",
  "H - Transport",
  "I - Accommodation and food",
  "J - Information and communication",
  "K - Finance and insurance",
  "L/M/N - Business services",
  "O - Public administration",
  "P - Education",
  "Q - Health",
  "R/S - Arts and other services",
  "T - Household employers"
)

sector_order_es <- c(
  "A - Agro y pesca",
  "B - Minas",
  "C - Manufactura",
  "D/E - Servicios publicos y agua",
  "F - Construccion",
  "G - Comercio",
  "H - Transporte",
  "I - Alojamiento y comida",
  "J - Informacion y comunicaciones",
  "K - Finanzas y seguros",
  "L/M/N - Servicios empresariales",
  "O - Administracion publica",
  "P - Educacion",
  "Q - Salud",
  "R/S - Arte y otros servicios",
  "T - Hogares empleadores"
)

sector_income_comparison <- sector_income_comparison %>%
  filter(as.character(sector_label_en) != "U - Extraterritorial orgs.") %>%
  mutate(
    sector_label_en = factor(
      sector_label_en,
      levels = unique(c(sector_order_en, sort(unique(as.character(sector_label_en)))))
    ),
    sector_label_es = factor(
      sector_label_es,
      levels = unique(c(sector_order_es, sort(unique(as.character(sector_label_es)))))
    )
  )

write.csv(
  sector_income_comparison,
  "Paper/tables/descriptive_wage_by_sector_year_size.csv",
  row.names = FALSE
)

sector_income_label_data <- sector_income_comparison %>%
  filter(tamano_empresa == "101+")

theme_sector_facet <- theme_classic(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 6),
    axis.text.y = element_text(size = 7),
    strip.text = element_text(face = "bold", size = 7),
    legend.position = "bottom",
    legend.box = "vertical",
    panel.spacing = unit(0.55, "lines")
  )

g_sector_income_comparison <- ggplot(
  sector_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.55) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 0.8,
    alpha = 0.9
  ) +
  geom_text(
    data = sector_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.22,
    size = 1.9,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.2, 1.05))) +
  facet_wrap(~ sector_label_en, scales = "free_y", ncol = 4) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 5.5,
    labels = percent_format(accuracy = 1),
    name = "% within sector-year"
  ) +
  scale_y_continuous(labels = comma) +
  labs(
    title = "Mean real hourly income by firm size and sector",
    subtitle = "2008 and 2025; bubble size is the employment share within each sector-year",
    x = "Firm size",
    y = "Mean hourly income"
  ) +
  coord_cartesian(clip = "off") +
  theme_sector_facet +
  theme(plot.margin = margin(5.5, 45, 5.5, 5.5))

g_sector_income_comparison_es <- ggplot(
  sector_income_comparison,
  aes(
    x = tamano_empresa,
    y = mean_income,
    color = year,
    linetype = year,
    group = year
  )
) +
  geom_line(linewidth = 0.55) +
  geom_point(
    aes(size = worker_share, fill = year),
    shape = 21,
    stroke = 0.8,
    alpha = 0.9
  ) +
  geom_text(
    data = sector_income_label_data,
    aes(label = year),
    hjust = 0,
    nudge_x = 0.22,
    size = 1.9,
    fontface = "bold",
    show.legend = FALSE
  ) +
  scale_x_discrete(expand = expansion(add = c(0.2, 1.05))) +
  facet_wrap(~ sector_label_es, scales = "free_y", ncol = 4) +
  scale_color_manual(
    values = income_comparison_colors,
    guide = "none"
  ) +
  scale_fill_manual(
    values = income_comparison_fills,
    guide = "none"
  ) +
  scale_linetype_manual(
    values = income_comparison_linetypes,
    guide = "none"
  ) +
  scale_size_area(
    max_size = 5.5,
    labels = percent_format(accuracy = 1),
    name = "% dentro de sector-a\u00f1o"
  ) +
  scale_y_continuous(labels = comma) +
  labs(
    title = "Ingreso laboral horario real promedio por tama\u00f1o de empresa y sector",
    subtitle = "2008 y 2025; la burbuja representa la participaci\u00f3n en el empleo dentro de cada sector-a\u00f1o",
    x = "Tama\u00f1o de empresa",
    y = "Ingreso horario promedio"
  ) +
  coord_cartesian(clip = "off") +
  theme_sector_facet +
  theme(plot.margin = margin(5.5, 45, 5.5, 5.5))

save_figure_versions(
  base_name = "fig71",
  plot_en = g_sector_income_comparison,
  plot_es = g_sector_income_comparison_es,
  width = 16,
  height = 12,
  dpi = 300
)

wage_gap_sample_2025 <- geih_model %>%
  filter(anio == 2025)

overall_mean_income_2025 <- weighted_mean(
  wage_gap_sample_2025$ingreso_hora_real,
  wage_gap_sample_2025$fex
)

sex_wage_gaps_2025 <- wage_gap_sample_2025 %>%
  mutate(
    group_en = if_else(female_worker == 1, "Women", "Men"),
    group_es = if_else(female_worker == 1, "Mujeres", "Hombres")
  ) %>%
  group_by(group_en, group_es) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  mutate(
    dimension_en = "Sex",
    dimension_es = "Sexo",
    group_order = match(group_en, c("Men", "Women"))
  )

formality_wage_gaps_2025 <- wage_gap_sample_2025 %>%
  filter(!is.na(formal)) %>%
  mutate(
    group_en = if_else(formal == 1, "Formal", "Informal"),
    group_es = if_else(formal == 1, "Formal", "Informal")
  ) %>%
  group_by(group_en, group_es) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  mutate(
    dimension_en = "Formality",
    dimension_es = "Formalidad",
    group_order = match(group_en, c("Formal", "Informal"))
  )

education_wage_gaps_2025 <- wage_gap_sample_2025 %>%
  filter(
    !grepl("No sabe|no informa", as.character(educacion), ignore.case = TRUE)
  ) %>%
  mutate(
    education_chr = as.character(educacion),
    group_en = case_when(
      grepl("Ning|No educ|Pre", education_chr, ignore.case = TRUE) ~ "Preschool or less",
      grepl("primaria|Primary", education_chr, ignore.case = TRUE) ~ "Primary",
      grepl("secundaria|^Media$|secondary|upper", education_chr, ignore.case = TRUE) ~ "Secondary",
      grepl("Superior|universitaria|Higher", education_chr, ignore.case = TRUE) ~ "Higher education",
      TRUE ~ education_chr
    ),
    group_es = case_when(
      grepl("Ning|No educ|Pre", education_chr, ignore.case = TRUE) ~ "Preescolar o menos",
      grepl("primaria|Primary", education_chr, ignore.case = TRUE) ~ "Basica primaria",
      grepl("secundaria|^Media$|secondary|upper", education_chr, ignore.case = TRUE) ~ "Secundaria",
      grepl("Superior|universitaria|Higher", education_chr, ignore.case = TRUE) ~ "Superior o universitaria",
      TRUE ~ education_chr
    )
  ) %>%
  group_by(group_en, group_es) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  mutate(
    dimension_en = "Education",
    dimension_es = "Educacion",
    group_order = match(group_en, education_order_en)
  )

sector_label_lookup <- sector_income_comparison %>%
  distinct(sector, sector_label_en, sector_label_es)

sector_wage_gaps_2025 <- wage_gap_sample_2025 %>%
  group_by(sector) %>%
  summarise(
    workers = sum(fex, na.rm = TRUE),
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  ) %>%
  left_join(sector_label_lookup, by = "sector") %>%
  filter(!is.na(sector_label_en)) %>%
  mutate(
    group_en = as.character(sector_label_en),
    group_es = as.character(sector_label_es),
    dimension_en = "Sector",
    dimension_es = "Sector",
    group_order = match(group_en, sector_order_en)
  ) %>%
  select(-sector_label_en, -sector_label_es)

wage_gaps_2025 <- bind_rows(
  sex_wage_gaps_2025,
  formality_wage_gaps_2025,
  education_wage_gaps_2025,
  sector_wage_gaps_2025
) %>%
  group_by(dimension_en, dimension_es) %>%
  mutate(employment_share = workers / sum(workers, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    gap_to_overall = 100 * (mean_income / overall_mean_income_2025 - 1),
    direction_en = if_else(
      gap_to_overall >= 0,
      "Above overall mean",
      "Below overall mean"
    ),
    direction_es = if_else(
      gap_to_overall >= 0,
      "Sobre el promedio total",
      "Debajo del promedio total"
    )
  ) %>%
  group_by(dimension_en, dimension_es) %>%
  mutate(ratio_to_lowest = mean_income / min(mean_income, na.rm = TRUE)) %>%
  ungroup()

write.csv(
  wage_gaps_2025,
  "Paper/tables/descriptive_wage_gaps_2025.csv",
  row.names = FALSE
)

wage_gap_table_data <- wage_gaps_2025 %>%
  mutate(
    dimension_en = factor(
      dimension_en,
      levels = c("Sex", "Formality", "Education", "Sector")
    ),
    table_order = if_else(
      dimension_en == "Sector",
      rank(gap_to_overall, ties.method = "first"),
      group_order
    )
  ) %>%
  arrange(dimension_en, table_order)

wage_gap_dimension <- as.character(wage_gap_table_data$dimension_en)
wage_gap_row_prefix <- ifelse(
  !duplicated(wage_gap_dimension),
  "    \\midrule\n    ",
  "    "
)
wage_gap_row_prefix[1] <- "    "

wage_gap_rows_2025 <- paste0(
  wage_gap_row_prefix,
  as.character(wage_gap_table_data$dimension_en),
  " & ",
  wage_gap_table_data$group_en,
  " & ",
  format_pct(wage_gap_table_data$employment_share),
  " & ",
  format_money(wage_gap_table_data$mean_income),
  " & ",
  format_pct_value(wage_gap_table_data$gap_to_overall),
  " & ",
  format_number(wage_gap_table_data$ratio_to_lowest, 2),
  " \\\\"
)

write_latex_table(
  c(
    "\\begin{table}[!htbp]",
    "  \\centering",
    "  \\caption{Mean real hourly labor income gaps by worker group, 2025}",
    "  \\label{tab:descriptive-wage-gaps-2025}",
    "  \\scriptsize",
    "  \\begin{tabular}{lp{0.34\\textwidth}rrrr}",
    "    \\toprule",
    "    Dimension & Group & Employment share & Mean income & Gap & Ratio \\\\",
    "    \\midrule",
    wage_gap_rows_2025,
    "    \\bottomrule",
    "  \\end{tabular}",
    "  \\vspace{0.3em}",
    "  \\begin{minipage}{0.95\\textwidth}",
    "  \\footnotesize",
    "  Notes: Statistics use 2025 observations and GEIH expansion weights. Employment shares are computed within each dimension. Mean income is real hourly labor income in constant 2025 pesos. The gap is the percent difference in each group's weighted mean relative to the overall 2025 weighted mean. The ratio divides each group's mean by the lowest mean within the same dimension. Formality rows exclude pensioned occupied workers. Sector rows omit extraterritorial organizations.",
    "  \\end{minipage}",
    "\\end{table}"
  ),
  "Paper/sections/descriptive_wage_gaps_2025_table.tex"
)

dimension_levels_en <- c("Sex", "Formality", "Education", "Sector")
dimension_levels_es <- c("Sexo", "Formalidad", "Educacion", "Sector")

wage_gaps_plot_2025 <- wage_gaps_2025 %>%
  mutate(
    dimension_en = factor(dimension_en, levels = dimension_levels_en),
    dimension_es = factor(dimension_es, levels = dimension_levels_es),
    plot_order = if_else(
      dimension_en == "Sector",
      rank(gap_to_overall, ties.method = "first"),
      group_order
    )
  ) %>%
  arrange(dimension_en, plot_order) %>%
  mutate(
    plot_label_en = factor(
      paste(as.character(dimension_en), group_en, sep = "___"),
      levels = paste(as.character(dimension_en), group_en, sep = "___")
    ),
    plot_label_es = factor(
      paste(as.character(dimension_es), group_es, sep = "___"),
      levels = paste(as.character(dimension_es), group_es, sep = "___")
    )
  )

theme_wage_gaps <- theme_classic(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(size = 10.5),
    axis.title = element_text(face = "bold"),
    axis.title.y = element_blank(),
    axis.text.y = element_text(size = 7),
    strip.background = element_blank(),
    strip.text.y = element_text(face = "bold", angle = 0, size = 9),
    legend.position = "none",
    panel.spacing = unit(0.8, "lines")
  )

g_wage_gaps_2025 <- ggplot(
  wage_gaps_plot_2025,
  aes(
    x = gap_to_overall,
    y = plot_label_en,
    fill = direction_en
  )
) +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "gray40",
    linewidth = 0.5
  ) +
  geom_col(width = 0.72) +
  facet_grid(
    dimension_en ~ .,
    scales = "free_y",
    space = "free_y"
  ) +
  scale_y_discrete(labels = function(x) sub("^.*___", "", x)) +
  scale_x_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0.08, 0.12))
  ) +
  scale_fill_manual(
    values = c(
      "Below overall mean" = "firebrick",
      "Above overall mean" = "darkgreen"
    )
  ) +
  labs(
    title = "Mean real hourly income gaps in 2025",
    subtitle = "Weighted means relative to the overall 2025 hourly-income mean",
    x = "Gap relative to overall mean"
  ) +
  theme_wage_gaps

g_wage_gaps_2025_es <- ggplot(
  wage_gaps_plot_2025,
  aes(
    x = gap_to_overall,
    y = plot_label_es,
    fill = direction_es
  )
) +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "gray40",
    linewidth = 0.5
  ) +
  geom_col(width = 0.72) +
  facet_grid(
    dimension_es ~ .,
    scales = "free_y",
    space = "free_y"
  ) +
  scale_y_discrete(labels = function(x) sub("^.*___", "", x)) +
  scale_x_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0.08, 0.12))
  ) +
  scale_fill_manual(
    values = c(
      "Debajo del promedio total" = "firebrick",
      "Sobre el promedio total" = "darkgreen"
    )
  ) +
  labs(
    title = "Brechas de ingreso laboral horario real en 2025",
    subtitle = "Promedios ponderados frente al promedio total de ingreso horario en 2025",
    x = "Brecha frente al promedio total"
  ) +
  theme_wage_gaps

save_figure_versions(
  base_name = "fig73",
  plot_en = g_wage_gaps_2025,
  plot_es = g_wage_gaps_2025_es,
  width = 10.5,
  height = 9.6,
  dpi = 300
)

snapshot_2025 <- employment_size %>%
  transmute(
    tamano_empresa,
    employment_share = share_last * 100
  ) %>%
  left_join(
    income_size_2025 %>%
      select(tamano_empresa, mean_income),
    by = "tamano_empresa"
  )

income_to_share_scale <- max(snapshot_2025$employment_share, na.rm = TRUE) /
  max(snapshot_2025$mean_income, na.rm = TRUE)

g_policy_snapshot_2025 <- ggplot(
  snapshot_2025,
  aes(x = tamano_empresa)
) +
  geom_col(
    aes(y = employment_share),
    fill = "darkgreen",
    alpha = 0.75,
    width = 0.68
  ) +
  geom_line(
    aes(y = mean_income * income_to_share_scale, group = 1),
    color = "darkblue",
    linewidth = 1.1
  ) +
  geom_point(
    aes(y = mean_income * income_to_share_scale),
    color = "darkblue",
    size = 3
  ) +
  scale_y_continuous(
    name = "Employment share",
    labels = function(x) paste0(x, "%"),
    sec.axis = sec_axis(
      ~ . / income_to_share_scale,
      name = "Mean hourly income",
      labels = comma
    ),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Employment and hourly income by firm size in 2025",
    subtitle = "Bars show employment share; points show mean real hourly income",
    x = "Firm size"
  ) +
  theme_paper +
  theme(
    axis.title.y = element_text(color = "darkgreen", face = "bold"),
    axis.title.y.right = element_text(color = "darkblue", face = "bold")
  )

g_policy_snapshot_2025_es <- g_policy_snapshot_2025 +
  scale_y_continuous(
    name = "Participaci\u00f3n en el empleo",
    labels = function(x) paste0(x, "%"),
    sec.axis = sec_axis(
      ~ . / income_to_share_scale,
      name = "Ingreso horario promedio",
      labels = comma
    ),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Empleo e ingreso horario por tama\u00f1o de empresa en 2025",
    subtitle = "Las barras muestran participaci\u00f3n en el empleo; los puntos muestran ingreso horario real promedio",
    x = "Tama\u00f1o de empresa"
  )

save_figure_versions(
  base_name = "fig66",
  plot_en = g_policy_snapshot_2025,
  plot_es = g_policy_snapshot_2025_es,
  width = 10,
  height = 6,
  dpi = 300
)

composition_2025_policy <- bind_rows(
  worker_balance_2025 %>%
    transmute(
      tamano_empresa,
      characteristic = "Formal",
      value = formal * 100
    ),
  worker_balance_2025 %>%
    transmute(
      tamano_empresa,
      characteristic = "Higher education",
      value = higher_education * 100
    )
)

g_policy_composition_2025 <- ggplot(
  composition_2025_policy,
  aes(
    x = tamano_empresa,
    y = value,
    color = characteristic,
    group = characteristic
  )
) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 3) +
  scale_color_manual(
    values = c(
      "Formal" = "darkblue",
      "Higher education" = "darkgreen"
    )
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0.08, 0.1))
  ) +
  labs(
    title = "Formality and higher education by firm size in 2025",
    subtitle = "Weighted shares in the baseline regression sample",
    x = "Firm size",
    y = "Share of workers",
    color = NULL
  ) +
  theme_paper

g_policy_composition_2025_es <- g_policy_composition_2025 +
  scale_color_manual(
    values = c(
      "Formal" = "darkblue",
      "Higher education" = "darkgreen"
    ),
    labels = c(
      "Formal" = "Formal",
      "Higher education" = "Educaci\u00f3n superior"
    )
  ) +
  labs(
    title = "Formalidad y educaci\u00f3n superior por tama\u00f1o de empresa en 2025",
    subtitle = "Participaciones ponderadas en la muestra base de regresi\u00f3n",
    x = "Tama\u00f1o de empresa",
    y = "Participaci\u00f3n de trabajadores",
    color = NULL
  )

save_figure_versions(
  base_name = "fig67",
  plot_en = g_policy_composition_2025,
  plot_es = g_policy_composition_2025_es,
  width = 10,
  height = 6,
  dpi = 300
)

g_employment_share_time <- ggplot(
  employment_size_year,
  aes(
    x = anio,
    y = employment_share * 100,
    color = tamano_empresa,
    group = tamano_empresa
  )
) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.7) +
  scale_x_continuous(breaks = seq(min(years), max(years), by = 4)) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title = "Employment share by firm size over time",
    subtitle = "Weighted shares in the baseline regression sample",
    x = "Year",
    y = "Employment share",
    color = "Firm size"
  ) +
  theme_paper

g_employment_share_time_es <- g_employment_share_time +
  labs(
    title = "Participaci\u00f3n del empleo por tama\u00f1o de empresa en el tiempo",
    subtitle = "Participaciones ponderadas en la muestra base de regresi\u00f3n",
    x = "A\u00f1o",
    y = "Participaci\u00f3n en el empleo",
    color = "Tama\u00f1o de empresa"
  )

save_figure_versions(
  base_name = "fig61",
  plot_en = g_employment_share_time,
  plot_es = g_employment_share_time_es,
  width = 10,
  height = 6,
  dpi = 300
)

income_year_size <- geih_model %>%
  group_by(anio, tamano_empresa) %>%
  summarise(
    mean_income = weighted_mean(ingreso_hora_real, fex),
    .groups = "drop"
  )

solo_income_year <- income_year_size %>%
  filter(tamano_empresa == "Solo") %>%
  select(anio, solo_mean_income = mean_income)

raw_premium_year <- income_year_size %>%
  left_join(solo_income_year, by = "anio") %>%
  mutate(raw_premium = 100 * (mean_income / solo_mean_income - 1)) %>%
  filter(tamano_empresa != "Solo")

write.csv(
  raw_premium_year,
  "Paper/tables/descriptive_raw_premium_by_year_size.csv",
  row.names = FALSE
)

g_raw_premium_time <- ggplot(
  raw_premium_year,
  aes(
    x = anio,
    y = raw_premium,
    color = tamano_empresa,
    group = tamano_empresa
  )
) +
  geom_hline(
    yintercept = 0,
    linetype = "dashed",
    color = "gray45",
    linewidth = 0.6
  ) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.7) +
  scale_x_continuous(breaks = seq(min(years), max(years), by = 4)) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title = "Raw firm-size wage premium over time",
    subtitle = "Weighted mean real hourly income relative to solo workers",
    x = "Year",
    y = "Raw premium relative to solo workers",
    color = "Firm size"
  ) +
  theme_paper

g_raw_premium_time_es <- g_raw_premium_time +
  labs(
    title = "Premium salarial bruto por tama\u00f1o de empresa en el tiempo",
    subtitle = "Ingreso laboral horario real promedio ponderado frente a trabajadores solos",
    x = "A\u00f1o",
    y = "Premium bruto frente a trabajadores solos",
    color = "Tama\u00f1o de empresa"
  )

save_figure_versions(
  base_name = "fig62",
  plot_en = g_raw_premium_time,
  plot_es = g_raw_premium_time_es,
  width = 10,
  height = 6,
  dpi = 300
)

composition_plot <- bind_rows(
  worker_balance %>%
    transmute(
      tamano_empresa,
      characteristic = "Women",
      value = women * 100
    ),
  worker_balance %>%
    transmute(
      tamano_empresa,
      characteristic = "Formal",
      value = formal * 100
    ),
  worker_balance %>%
    transmute(
      tamano_empresa,
      characteristic = "Higher education",
      value = higher_education * 100
    )
)

composition_plot_es <- bind_rows(
  worker_balance %>%
    transmute(
      tamano_empresa,
      characteristic = "Mujeres",
      value = women * 100
    ),
  worker_balance %>%
    transmute(
      tamano_empresa,
      characteristic = "Formal",
      value = formal * 100
    ),
  worker_balance %>%
    transmute(
      tamano_empresa,
      characteristic = "Educaci\u00f3n superior",
      value = higher_education * 100
    )
)

g_worker_composition <- ggplot(
  composition_plot,
  aes(
    x = tamano_empresa,
    y = value,
    color = characteristic,
    group = characteristic
  )
) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.8) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  scale_color_manual(
    values = c(
      "Women" = "darkred",
      "Formal" = "darkblue",
      "Higher education" = "darkgreen"
    )
  ) +
  labs(
    title = "Worker composition by firm size",
    subtitle = "Weighted shares in the baseline regression sample",
    x = "Firm size",
    y = "Share of workers",
    color = NULL
  ) +
  theme_paper

g_worker_composition_es <- ggplot(
  composition_plot_es,
  aes(
    x = tamano_empresa,
    y = value,
    color = characteristic,
    group = characteristic
  )
) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.8) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  scale_color_manual(
    values = c(
      "Mujeres" = "darkred",
      "Formal" = "darkblue",
      "Educaci\u00f3n superior" = "darkgreen"
    )
  ) +
  labs(
    title = "Composici\u00f3n de trabajadores por tama\u00f1o de empresa",
    subtitle = "Participaciones ponderadas en la muestra base de regresi\u00f3n",
    x = "Tama\u00f1o de empresa",
    y = "Participaci\u00f3n de trabajadores",
    color = NULL
  ) +
  theme_paper

save_figure_versions(
  base_name = "fig63",
  plot_en = g_worker_composition,
  plot_es = g_worker_composition_es,
  width = 10,
  height = 6,
  dpi = 300
)

income_checks <- geih_model %>% group_by(anio) %>% summarise(
  observations = n(), workers = sum(fex),
  mean_hourly = weighted_mean(ingreso_hora_real, fex),
  mean_weekly_hours = weighted_mean(horas, fex),
  mean_monthly = weighted_mean(ingreso_hora_real * horas * 52/12, fex), .groups = "drop")
write.csv(income_checks, "Paper/tables/primary_income_descriptive_checks.csv", row.names = FALSE)
solo_education <- geih_model %>% filter(anio == 2025, formal == 1, tamano_empresa == "Solo") %>%
  group_by(higher_education) %>% summarise(observations = n(), workers = sum(fex),
    own_account_pct = 100 * weighted_mean(posicion_ocupacional_label == "Trabajador por cuenta propia", fex),
    mean_hourly = weighted_mean(ingreso_hora_real, fex), .groups = "drop")
write.csv(solo_education, "Paper/tables/formal_solo_education_2025.csv", row.names = FALSE)
