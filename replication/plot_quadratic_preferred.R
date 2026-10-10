if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(ggplot2); library(dplyr); library(scales)})
curves <- read.csv(file.path(paper, "replication/quadratic_output/curves.csv")) %>% filter(top == 150)
points <- read.csv(file.path(paper, "replication/preferred_output/profiles.csv")) %>% filter(reference == "Solo")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
assigned <- c(1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, 150)
points$size_value <- assigned[match(points$size, sizes)]
for (lang in c("en", "es")) {
  es <- lang == "es"
  labels <- if (es) c("Formales", "Informales") else c("Formal", "Informal")
  pdat <- points %>% mutate(group = factor(group, levels = c("Formal", "Informal"), labels = labels))
  cdat <- curves %>% mutate(group = factor(group, levels = c("Formal", "Informal"), labels = labels))
  p <- ggplot() +
    geom_hline(yintercept = 0, color = "gray55", linetype = "dashed") +
    geom_ribbon(data = cdat, aes(size_value, ymin = ci_low, ymax = ci_high), fill = "#0072B2", alpha = .13) +
    geom_line(data = cdat, aes(size_value, premium, color = "quadratic"), linewidth = .9) +
    geom_errorbar(data = pdat, aes(size_value, ymin = ci_low, ymax = ci_high), width = .045, color = "gray35") +
    geom_point(data = pdat, aes(size_value, premium, color = "categorical"), size = 2.5) +
    facet_wrap(~group, nrow = 1) +
    scale_x_log10(breaks = c(1, 2.5, 5, 10, 25, 50, 150), labels = c("1", "2.5", "5", "10", "25", "50", "150")) +
    scale_y_continuous(labels = label_percent(scale = 1)) +
    scale_color_manual(values = c(categorical = "#333333", quadratic = "#0072B2"), name = NULL,
      breaks = c("categorical", "quadratic"), labels = if (es) c("Modelo con dummies", "Modelo cuadr\u00e1tico") else c("Categorical model", "Quadratic model")) +
    guides(color = guide_legend(override.aes = list(shape = c(16, NA), linetype = c(0, 1)))) +
    labs(title = if (es) "Aproximaci\u00f3n cuadr\u00e1tica con los controles preferidos" else "Quadratic approximation with preferred controls",
      subtitle = if (es) "Referencia: solos del mismo grupo. Barras y bandas: IC del 95%. Tama\u00f1o asignado a 101+: 150." else
        "Relative to solo workers of the same status. Bars and bands: 95% CIs. Assigned size for 101+: 150.",
      x = if (es) "Tama\u00f1o asignado de empresa (escala logar\u00edtmica)" else "Assigned firm size (log scale)",
      y = if (es) "Premium salarial (%)" else "Wage premium (%)") +
    theme_classic(base_size = 12) + theme(plot.title = element_text(face = "bold", size = 15),
      plot.subtitle = element_text(size = 10.5), axis.title = element_text(face = "bold"),
      legend.position = "bottom", strip.background = element_rect(fill = "white", color = "black"),
      strip.text = element_text(face = "bold"))
  ggsave(file.path(paper, "Paper/figures", paste0("preferred_quadratic_", lang, ".png")),
    p, width = 12, height = 6, dpi = 300, bg = "white")
}
