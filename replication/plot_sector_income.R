if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(ggplot2); library(dplyr); library(scales)})

dat <- read.csv(file.path(paper, "Paper/tables/descriptive_wage_by_sector_year_size.csv"),
  fileEncoding = "UTF-8")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
sector_order <- c("A", "B", "C", "D/E", "F", "G", "H", "I", "J", "K", "L/M/N", "O", "P", "Q", "R/S", "T")
labels_en <- c("Agriculture", "Mining", "Manufacturing", "Utilities and water",
  "Construction", "Commerce", "Transport", "Accommodation and food",
  "Information and communication", "Finance and insurance", "Business services",
  "Public administration", "Education", "Health", "Arts and other services", "Household employers")
labels_es <- c("Agro y pesca", "Minas", "Manufactura", "Servicios p\u00fablicos y agua",
  "Construcci\u00f3n", "Comercio", "Transporte", "Alojamiento y comida",
  "Informaci\u00f3n y comunicaciones", "Finanzas y seguros", "Servicios empresariales",
  "Administraci\u00f3n p\u00fablica", "Educaci\u00f3n", "Salud", "Arte y otros servicios", "Hogares empleadores")
dat <- dat %>% mutate(sector_code = sub(" - .*", "", sector_label_en),
  tamano_empresa = factor(tamano_empresa, levels = sizes), year = factor(anio, levels = c(2008, 2025)))
stopifnot(!anyDuplicated(dat[c("anio", "sector_code", "tamano_empresa")]),
  setequal(unique(dat$sector_code), sector_order), !anyNA(dat$tamano_empresa),
  !anyNA(dat$year), all(is.finite(dat$mean_income)), all(dat$mean_income > 0),
  all(dat$worker_share >= 0 & dat$worker_share <= 1))
shares <- dat %>% group_by(year, sector_code) %>% summarise(total = sum(worker_share), .groups = "drop")
stopifnot(nrow(shares) == 32L, all(abs(shares$total - 1) < 1e-8))

# Export the endpoint comparisons for the accompanying paragraph.
ratios <- dat %>% filter(tamano_empresa %in% c("Solo", "101+")) %>%
  group_by(year, sector_code) %>% summarise(
    ratio = mean_income[tamano_empresa == "101+"] / mean_income[tamano_empresa == "Solo"], .groups = "drop")
stopifnot(nrow(ratios) == 32L, all(is.finite(ratios$ratio)), all(ratios$ratio > 0))
write.csv(ratios, file.path(paper, "Paper/tables/sector_endpoint_ratios.csv"), row.names = FALSE)

colors <- c("2008" = "#D55E00", "2025" = "#0072B2")
fills <- c("2008" = "white", "2025" = "#0072B2")
linetypes <- c("2008" = "dashed", "2025" = "solid")
for (lang in c("en", "es")) {
  es <- lang == "es"
  plot_data <- dat %>% mutate(sector_label = factor(sector_code, levels = sector_order,
    labels = if (es) labels_es else labels_en))
  p <- ggplot(plot_data, aes(tamano_empresa, mean_income, color = year, linetype = year, group = year)) +
    geom_line(linewidth = .45) +
    geom_point(aes(size = worker_share, fill = year), shape = 21, stroke = .55) +
    facet_wrap(~sector_label, ncol = 2, scales = "free_y") +
    scale_color_manual(values = colors, name = NULL) +
    scale_fill_manual(values = fills, name = NULL) +
    scale_linetype_manual(values = linetypes, name = NULL) +
    scale_size_area(max_size = 3.8, breaks = c(.25, .50, .75),
      labels = label_percent(accuracy = 1),
      name = if (es) "% dentro de sector-a\u00f1o" else "% within sector-year") +
    scale_x_discrete(expand = expansion(add = c(.3, .4)), drop = FALSE) +
    scale_y_continuous(labels = label_comma(accuracy = 1), breaks = breaks_pretty(n = 3),
      expand = expansion(mult = c(.12, .18))) +
    guides(color = guide_legend(order = 1, override.aes = list(size = 2.5)),
      fill = guide_legend(order = 1), linetype = guide_legend(order = 1),
      size = guide_legend(order = 2, override.aes = list(color = "gray30", fill = "white", linetype = 0))) +
    labs(x = if (es) "Tama\u00f1o de empresa" else "Firm size",
      y = if (es) "Ingreso horario promedio (pesos de 2025)" else "Mean hourly income (2025 COP)") +
    theme_classic(base_size = 10) + theme(
      axis.title = element_text(size = 10, face = "bold"),
      axis.text = element_text(size = 8.5, color = "black"),
      axis.text.x = element_text(angle = 45, hjust = 1),
      axis.ticks.length = unit(2, "pt"),
      strip.background = element_rect(fill = "white", color = "gray45", linewidth = .35),
      strip.text = element_text(face = "bold", size = 9.5, margin = margin(t = 3, b = 3)),
      panel.spacing.x = unit(10, "pt"), panel.spacing.y = unit(5, "pt"),
      legend.position = "bottom", legend.box = "horizontal", legend.text = element_text(size = 8.5),
      legend.title = element_text(size = 8.5), legend.key.width = unit(13, "pt"),
      legend.key.height = unit(12, "pt"), legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(t = 2), plot.margin = margin(3, 5, 3, 3))
  rendered <- ggplot_build(p)
  stopifnot(nrow(rendered$layout$layout) == 16L, max(rendered$layout$layout$COL) == 2L,
    nrow(rendered$data[[2]]) == nrow(dat), all(is.finite(rendered$data[[2]]$y)),
    all(vapply(seq_len(16), function(i) {
      values <- rendered$data[[2]]$y[rendered$data[[2]]$PANEL == i]
      limits <- rendered$layout$panel_params[[i]]$y.range
      all(values > limits[1] & values < limits[2])
    }, logical(1))))
  base <- file.path(paper, "Paper/figures", paste0("fig71_", lang))
  ggsave(paste0(base, ".png"), p, width = 6.5, height = 7, dpi = 400, bg = "white")
  ggsave(paste0(base, ".pdf"), p, device = grDevices::pdf, version = "1.5", useDingbats = FALSE,
    width = 6.5, height = 7, bg = "white")
}
message("Regenerated the sector figure in two columns, in English and Spanish.")
