if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
local_r_lib <- file.path(dirname(paper), "CJC-Monitor/.Rlib")
if (dir.exists(local_r_lib)) {
  .libPaths(c(local_r_lib, .libPaths()))
}

paper_root <- file.path(paper, "build/descriptive_refresh")
dir.create(paper_root, recursive = TRUE, showWarnings = FALSE)
geih_personas_data_path <- function() file.path(paper, "data/GEIH_primary_income_2008_2025.dta")

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
  library(stringr)
})

figure_path <- function(file) file.path(paper_root, "Paper", "figures", file)
section_path <- function(file) file.path(paper_root, "Paper", "sections", file)
table_path <- function(file) file.path(paper_root, "Paper", "tables", file)

dir.create(file.path(paper_root, "Paper", "figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(paper_root, "Paper", "sections"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(paper_root, "Paper", "tables"), recursive = TRUE, showWarnings = FALSE)

size_levels <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")

minimum_wage <- tibble::tribble(
  ~anio, ~smmlv_monthly,
  2008, 461500,
  2009, 496900,
  2010, 515000,
  2011, 535600,
  2012, 566700,
  2013, 589500,
  2014, 616000,
  2015, 644350,
  2016, 689455,
  2017, 737717,
  2018, 781242,
  2019, 828116,
  2020, 877803,
  2021, 908526,
  2022, 1000000,
  2023, 1160000,
  2024, 1300000,
  2025, 1423500
) |>
  mutate(
    legal_weekly_hours = case_when(
      anio <= 2022 ~ 48,
      anio == 2023 ~ 47.5,
      anio == 2024 ~ 46.5,
      anio == 2025 ~ 45,
      TRUE ~ 48
    ),
    smmlv_hourly = smmlv_monthly * 12 / (legal_weekly_hours * 52)
  )

geih <- read_dta(geih_personas_data_path())

sample_2025 <- geih |>
  mutate(
    tamano_empresa = factor(as.character(tamano_empresa), levels = size_levels),
    formality_en = if_else(formal == 1, "Formal workers", "Informal workers"),
    formality_es = if_else(formal == 1, "Trabajadores formales", "Trabajadores informales")
  ) |>
  left_join(minimum_wage, by = "anio") |>
  filter(
    anio == 2025,
    !is.na(ingreso_laboral_hora),
    ingreso_laboral_hora > 0,
    !is.na(smmlv_hourly),
    !is.na(tamano_empresa),
    !is.na(formal),
    !is.na(fex),
    fex > 0
  ) |>
  mutate(
    wage_min_ratio = ingreso_laboral_hora / smmlv_hourly,
    log2_ratio = log2(wage_min_ratio),
    y_index = as.integer(tamano_empresa)
  ) |>
  filter(is.finite(log2_ratio))

weighted_share <- function(condition, weight) {
  sum(weight[condition], na.rm = TRUE) / sum(weight, na.rm = TRUE)
}

weighted_quantile <- function(x, w, probs) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  x <- x[ok]
  w <- w[ok]
  if (length(x) == 0 || sum(w) == 0) {
    return(rep(NA_real_, length(probs)))
  }
  ord <- order(x)
  x <- x[ord]
  w <- w[ord]
  cw <- cumsum(w) / sum(w)
  vapply(probs, function(p) x[which(cw >= p)[1]], numeric(1))
}

share_table <- sample_2025 |>
  group_by(formality_en, formality_es, tamano_empresa) |>
  summarise(
    workers = sum(fex, na.rm = TRUE),
    below_09 = weighted_share(wage_min_ratio < 0.9, fex),
    around_min = weighted_share(wage_min_ratio >= 0.9 & wage_min_ratio <= 1.1, fex),
    above_11 = weighted_share(wage_min_ratio > 1.1, fex),
    below_min = weighted_share(wage_min_ratio < 1, fex),
    q25 = weighted_quantile(wage_min_ratio, fex, 0.25),
    median = weighted_quantile(wage_min_ratio, fex, 0.50),
    q75 = weighted_quantile(wage_min_ratio, fex, 0.75),
    .groups = "drop"
  ) |>
  group_by(formality_en) |>
  mutate(share_within_formality = workers / sum(workers)) |>
  ungroup() |>
  arrange(formality_en, tamano_empresa)

readr::write_csv(
  share_table |>
    select(
      formality_en, firm_size = tamano_empresa, workers, share_within_formality,
      below_09, around_min, above_11, below_min, q25, median, q75
    ),
  table_path("minimum_wage_bunching_2025.csv")
)

format_pct <- function(x, digits = 1) paste0(sprintf(paste0("%.", digits, "f"), 100 * x), "\\%")
format_ratio <- function(x) sprintf("%.2f", x)

table_lines <- c()
for (status in c("Formal workers", "Informal workers")) {
  status_rows <- share_table |> filter(formality_en == status)
  table_lines <- c(
    table_lines,
    "    \\midrule",
    paste0("    \\multicolumn{8}{l}{\\textit{", status, "}} \\\\")
  )
  for (i in seq_len(nrow(status_rows))) {
    row <- status_rows[i, ]
    table_lines <- c(
      table_lines,
      paste0(
        "    ", as.character(row$tamano_empresa), " & ",
        format_pct(row$share_within_formality), " & ",
        format_pct(row$below_09), " & ",
        format_pct(row$around_min), " & ",
        format_pct(row$above_11), " & ",
        format_ratio(row$q25), " & ",
        format_ratio(row$median), " & ",
        format_ratio(row$q75), " \\\\"
      )
    )
  }
}

minimum_table <- c(
  "\\begin{table}[htbp]",
  "  \\centering",
  "  \\caption{Distribution of hourly wages relative to the statutory hourly minimum, 2025}",
  "  \\label{tab:minimum-wage-bunching-2025}",
  "  \\small",
  "  \\begin{tabular}{lrrrrrrr}",
  "    \\toprule",
  "    Firm size & Employment share & $<0.9$ & $0.9$--$1.1$ & $>1.1$ & P25 & Median & P75 \\\\",
  table_lines,
  "    \\bottomrule",
  "  \\end{tabular}",
  "  \\vspace{0.3em}",
  "  \\begin{minipage}{0.95\\textwidth}",
  "  \\footnotesize",
  "  Notes: The table uses 2025 observations and GEIH expansion weights. Wages are expressed relative to the statutory hourly minimum, computed as the monthly legal minimum wage divided by the approximate average legal monthly hours in 2025. The columns $<0.9$, $0.9$--$1.1$, and $>1.1$ report the weighted share of workers in each range. Employment shares are computed within each formality group.",
  "  \\end{minipage}",
  "\\end{table}"
)
writeLines(minimum_table, section_path("minimum_wage_bunching_2025_table.tex"), useBytes = TRUE)

make_density_data <- function(data, formality_col = "formality_en") {
  data <- data |> mutate(formality_plot = .data[[formality_col]])
  panel_totals <- data |> group_by(formality_plot) |>
    summarise(panel_weight = sum(fex), .groups = "drop")
  # A common Gaussian bandwidth makes smoothing comparable across all groups.
  curves <- data |> group_by(formality_plot, tamano_empresa, y_index) |>
    group_modify(~{
      den <- stats::density(.x$log2_ratio, weights = .x$fex / sum(.x$fex),
                            bw = 0.12, kernel = "gaussian", n = 512,
                            from = log2(0.25), to = log2(8))
      tibble(x = den$x, density = den$y, group_weight = sum(.x$fex),
             scaled_height = 0.72 * den$y / max(den$y))
    }) |> ungroup() |>
    left_join(panel_totals, by = "formality_plot") |>
    mutate(employment_share = group_weight / panel_weight,
           share_label = percent(employment_share, accuracy = 0.1))
  stopifnot(nrow(curves) == 18L * 512L, all(is.finite(curves$density)),
            all(curves$density >= 0), all(curves$scaled_height <= 0.72 + 1e-12))
  curves
}

plot_distribution <- function(lang = c("en", "es")) {
  lang <- match.arg(lang)
  formality_col <- if (lang == "en") "formality_en" else "formality_es"
  plot_data <- make_density_data(sample_2025, formality_col = formality_col)

  share_labels <- plot_data |>
    distinct(formality_plot, tamano_empresa, y_index, share_label)

  panel_labels <- plot_data |>
    distinct(formality_plot) |>
    mutate(x = log2(7.7), y = length(size_levels) + 0.85)

  if (lang == "en") {
    title <- "Distribution of hourly wages relative to the minimum wage, 2025"
    subtitle <- "Kernel densities by firm size and formality; vertical line marks the hourly benchmark"
    xlab <- "Hourly wage / statutory hourly minimum, log scale"
    ylab <- "Firm size"
    note <- "Share"
    file <- "fig77_en.png"
  } else {
    title <- "Distribución del ingreso por hora relativo al salario mínimo, 2025"
    subtitle <- "Densidades kernel por tamaño de empresa y formalidad; la línea vertical marca el referente horario"
    xlab <- "Ingreso por hora / salario mínimo horario, escala logarítmica"
    ylab <- "Tamaño de empresa"
    note <- "Part."
    file <- "fig77_es.png"
  }

  ggplot(plot_data) +
    geom_ribbon(
      aes(
        x = x, group = interaction(formality_plot, tamano_empresa),
        ymin = y_index,
        ymax = y_index + scaled_height,
        fill = formality_plot
      ),
      color = NA,
      alpha = 0.84
    ) +
    geom_hline(
      yintercept = seq_along(size_levels),
      color = "#d8d8d8",
      linewidth = 0.25
    ) +
    geom_vline(xintercept = 0, color = "#333333", linetype = "dashed", linewidth = 0.45) +
    geom_text(
      data = share_labels,
      aes(x = log2(7.7), y = y_index + 0.34, label = share_label),
      inherit.aes = FALSE,
      hjust = 1,
      size = 2.6,
      color = "#3f3f3f"
    ) +
    geom_text(
      data = panel_labels,
      aes(x = x, y = y, label = note),
      inherit.aes = FALSE,
      hjust = 1,
      size = 2.6,
      color = "#3f3f3f",
      fontface = "bold"
    ) +
    facet_wrap(vars(formality_plot), ncol = 2) +
    scale_x_continuous(
      breaks = log2(c(0.25, 0.5, 1, 2, 4, 8)),
      labels = c("0.25", "0.5", "1", "2", "4", "8"),
      limits = c(log2(0.25), log2(8.3)),
      expand = expansion(mult = c(0.01, 0.03))
    ) +
    scale_y_continuous(
      breaks = seq_along(size_levels) + 0.30,
      labels = size_levels,
      limits = c(0.8, length(size_levels) + 1.1),
      expand = expansion(mult = c(0, 0))
    ) +
    scale_fill_manual(values = c(
      "Formal workers" = "#006E9C",
      "Informal workers" = "#D55E00",
      "Trabajadores formales" = "#006E9C",
      "Trabajadores informales" = "#D55E00"
    ), guide = "none") +
    labs(title = title, subtitle = subtitle, x = xlab, y = ylab) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 15, color = "#111111"),
      plot.subtitle = element_text(size = 10.5, color = "#333333"),
      strip.text = element_text(face = "bold", size = 11),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(color = "#e6e6e6", linewidth = 0.3),
      axis.text.y = element_text(size = 9, color = "#222222"),
      axis.text.x = element_text(size = 9, color = "#222222"),
      axis.title = element_text(size = 10, color = "#222222"),
      plot.margin = margin(10, 14, 10, 10)
    )

  ggsave(figure_path(file), width = 11.2, height = 6.6, dpi = 320, bg = "white")
}

plot_distribution("en")
plot_distribution("es")

monthly <- sample_2025 %>% mutate(ratio = primary_monthly / smmlv_monthly) %>%
  group_by(formality_en, tamano_empresa) %>% summarise(workers = sum(fex),
    below_09 = weighted_share(ratio < .9, fex),
    around_min = weighted_share(ratio >= .9 & ratio <= 1.1, fex),
    above_11 = weighted_share(ratio > 1.1, fex),
    q25 = weighted_quantile(ratio, fex, .25), median = weighted_quantile(ratio, fex, .5),
    q75 = weighted_quantile(ratio, fex, .75), .groups = "drop") %>%
  group_by(formality_en) %>% mutate(share_within_formality = workers/sum(workers)) %>%
  ungroup() %>% arrange(formality_en, tamano_empresa)
write.csv(monthly, table_path("minimum_wage_monthly_bunching_2025.csv"), row.names = FALSE)
monthly_lines <- c("\\begin{table}")
for (status in c("Formal workers", "Informal workers")) {
  x <- monthly[monthly$formality_en == status, ]
  for (j in seq_len(nrow(x))) {
    r <- x[j, ]
    monthly_lines <- c(monthly_lines, paste0(as.character(r$tamano_empresa), " & ",
      paste(c(format_pct(unlist(r[c("share_within_formality", "below_09", "around_min", "above_11")])),
        format_ratio(unlist(r[c("q25", "median", "q75")]))), collapse = " & "), " \\\\"))
  }
}
writeLines(c(monthly_lines, "\\end{table}"), section_path("minimum_wage_monthly_bunching_2025_table.tex"))

message("Minimum wage distribution figures and table generated.")
