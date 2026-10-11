if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(ggplot2); library(dplyr); library(scales)})
out <- file.path(paper, "replication/preferred_output")
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
profiles <- read.csv(file.path(out, "profiles.csv"))
annual <- read.csv(file.path(out, "annual_profiles.csv"))
theme_paper <- theme_classic(base_size = 12) + theme(
  plot.title = element_text(face = "bold", size = 15), plot.subtitle = element_text(size = 11),
  axis.title = element_text(face = "bold"), legend.position = "bottom",
  strip.background = element_rect(fill = "white", color = "black"), strip.text = element_text(face = "bold"),
  axis.text.x = element_text(angle = 35, hjust = 1))
for (lang in c("en", "es")) {
  es <- lang == "es"
  group_labels <- if (es) c("Formales", "Informales") else c("Formal", "Informal")
  annotate <- function(x) x %>% mutate(group = factor(group, levels = c("Formal", "Informal"), labels = group_labels),
    size = factor(size, levels = sizes), significant = p.value < .05)
  save_plot <- function(p, name) ggsave(file.path(paper, "Paper/figures", paste0(name, "_", lang, ".png")),
    p, width = 12, height = 6, dpi = 300, bg = "white")
  shape_scale <- function() scale_shape_manual(values = c(`FALSE` = 1, `TRUE` = 16), name = NULL,
    labels = if (es) c("No significativo", "Significativo al 5%") else c("Not significant", "Significant at 5%"))
  xlab <- if (es) "Tama\u00f1o de empresa" else "Firm size"
  ylab <- if (es) "Premium salarial (%)" else "Wage premium (%)"
  note <- if (es) "Referencia: trabajadores solos del mismo grupo. Intervalos de confianza del 95%." else
    "Relative to solo workers of the same status. 95% confidence intervals."
  pdat <- annotate(profiles %>% filter(reference == "Solo"))
  p <- ggplot(pdat, aes(size, premium, group = group)) +
    geom_hline(yintercept = 0, color = "gray50", linetype = "dashed") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = .12, color = "gray35") +
    geom_line(color = "#0072B2", linewidth = .7) + geom_point(aes(shape = significant), color = "#0072B2", size = 2.8) +
    geom_text(aes(y = pmax(ci_high + 2.5, 4), label = sprintf("%.1f%%", premium)), size = 3.1) +
    facet_wrap(~group, nrow = 1) + shape_scale() +
    scale_y_continuous(labels = label_percent(scale = 1), expand = expansion(mult = c(.07, .14))) +
    labs(title = if (es) "Premium por tama\u00f1o y formalidad: especificaci\u00f3n preferida" else
      "Firm-size premiums by formality: preferred specification", subtitle = note, x = xlab, y = ylab) + theme_paper
  save_plot(p, "preferred_formality_premiums")
  pdat <- annotate(annual %>% filter(year %in% c(2008, 2025))) %>% mutate(year = factor(year))
  dodge <- position_dodge(width = .25)
  p <- ggplot(pdat, aes(size, premium, color = year, linetype = year, group = year)) +
    geom_hline(yintercept = 0, color = "gray50", linetype = "dashed") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = .10, alpha = .7, position = dodge) +
    geom_line(linewidth = .8, position = dodge) + geom_point(aes(shape = year), size = 2.6, position = dodge) +
    facet_wrap(~group, nrow = 1) + scale_color_manual(values = c(`2008` = "#D95F02", `2025` = "#0072B2")) +
    scale_linetype_manual(values = c(`2008` = "dashed", `2025` = "solid")) +
    scale_shape_manual(values = c(`2008` = 1, `2025` = 16)) + scale_y_continuous(labels = label_percent(scale = 1)) +
    labs(title = if (es) "Premium por tama\u00f1o y formalidad, 2008 y 2025" else
      "Firm-size premiums by formality, 2008 and 2025", subtitle = note, x = xlab, y = ylab,
      color = NULL, linetype = NULL, shape = NULL) + theme_paper
  save_plot(p, "preferred_formality_endpoints")
  pdat <- annotate(annual %>% filter(size == "101+")) %>% mutate(segment = year > 2020)
  p <- ggplot(pdat, aes(year, premium, group = segment)) +
    geom_hline(yintercept = 0, color = "gray50", linetype = "dashed") +
    geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "#0072B2", alpha = .14) +
    geom_line(color = "#0072B2", linewidth = .8) + geom_point(aes(shape = significant), color = "#0072B2", size = 2.5) +
    facet_wrap(~group, nrow = 1) + shape_scale() + scale_x_continuous(breaks = c(2008, 2013, 2019, 2025)) +
    scale_y_continuous(labels = label_percent(scale = 1)) +
    labs(title = if (es) "Premium de 101+ frente a solos: controles preferidos en cada a\u00f1o" else
      "101+/solo premiums: preferred controls in each year", subtitle = note,
      x = if (es) "A\u00f1o" else "Year", y = ylab) + theme_paper + theme(axis.text.x = element_text(angle = 0, hjust = .5))
  save_plot(p, "preferred_large_firm_dynamics")
}
