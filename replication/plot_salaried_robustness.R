if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(ggplot2); library(dplyr); library(scales)})
out <- file.path(paper, "replication/salaried_output")
sizes <- c("2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
dat <- read.csv(file.path(out, "contrasts.csv")) %>%
  filter(sample == "Salaried", reference == "Solo", clustering == "Sector-department") %>%
  mutate(size = factor(size, levels = sizes), significant = p.value < .05,
    label_y = pmax(ci_high + 2.5, 4), label = sprintf("%.1f%%", premium))
stopifnot(nrow(dat) == 16L, !anyDuplicated(dat[c("group", "size")]))

# Match the full-sample figure's automatic range, including its label positions.
reference <- read.csv(file.path(paper, "replication/preferred_output/profiles.csv")) %>%
  filter(reference == "Solo")
stopifnot(nrow(reference) == 16L)
raw_range <- range(0, reference$ci_low, reference$ci_high, pmax(reference$ci_high + 2.5, 4))
y_limits <- raw_range + diff(raw_range) * c(-.07, .14)
stopifnot(all(dat$ci_low >= y_limits[1]), all(dat$label_y <= y_limits[2]))
dat$axis_min <- y_limits[1]
dat$axis_max <- y_limits[2]
write.csv(dat, file.path(out, "figure_profiles.csv"), row.names = FALSE, fileEncoding = "UTF-8")

theme_paper <- theme_classic(base_size = 12) + theme(
  plot.title = element_text(face = "bold", size = 15), plot.subtitle = element_text(size = 11),
  axis.title = element_text(face = "bold"), legend.position = "bottom",
  strip.background = element_rect(fill = "white", color = "black"),
  strip.text = element_text(face = "bold"), axis.text.x = element_text(angle = 35, hjust = 1))
for (lang in c("en", "es")) {
  es <- lang == "es"
  pdat <- dat %>% mutate(group = factor(group, levels = c("Formal", "Informal"),
    labels = if (es) c("Formales", "Informales") else c("Formal", "Informal")))
  p <- ggplot(pdat, aes(size, premium, group = group)) +
    geom_hline(yintercept = 0, color = "gray50", linetype = "dashed") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = .12, color = "gray35") +
    geom_line(color = "#0072B2", linewidth = .7) +
    geom_point(aes(shape = significant), color = "#0072B2", size = 2.8) +
    geom_text(aes(y = label_y, label = label), size = 3.1) +
    facet_wrap(~group, nrow = 1) +
    scale_shape_manual(values = c("FALSE" = 1, "TRUE" = 16), name = NULL,
      labels = if (es) c("No significativo", "Significativo al 5%") else
        c("Not significant", "Significant at 5%")) +
    scale_y_continuous(limits = y_limits, labels = label_percent(scale = 1),
      expand = expansion(mult = 0)) +
    labs(title = if (es) "Premium por tama\u00f1o y formalidad: solo asalariados" else
      "Firm-size premiums by formality: salaried workers",
      subtitle = if (es) "Referencia: asalariados solos del mismo grupo. Intervalos de confianza del 95%." else
        "Relative to solo employees of the same status. 95% confidence intervals.",
      x = if (es) "Tama\u00f1o de empresa" else "Firm size",
      y = if (es) "Premium salarial (%)" else "Wage premium (%)") + theme_paper
  rendered <- ggplot_build(p)
  stopifnot(nrow(rendered$data[[2]]) == 16L, nrow(rendered$data[[4]]) == 16L,
    all(is.finite(rendered$data[[2]]$ymin)), all(is.finite(rendered$data[[2]]$ymax)),
    all(vapply(rendered$layout$panel_params, function(x) max(abs(x$y.range-y_limits)) < 1e-9, logical(1))))
  ggsave(file.path(paper, "Paper/figures", paste0("salaried_formality_premiums_", lang, ".png")),
    p, width = 12, height = 6, dpi = 300, bg = "white")
}
message("Generated English and Spanish salaried profiles with the full-sample figure's vertical scale.")
