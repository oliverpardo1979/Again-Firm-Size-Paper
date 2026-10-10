if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script, winslash = "/")))
.libPaths(c(file.path(dirname(paper), "CJC-Monitor/.Rlib"), .libPaths()))
suppressPackageStartupMessages({library(ggplot2); library(dplyr); library(scales)})
out <- file.path(paper, "replication/regression_output")
read_output <- function(name) read.csv(file.path(out, paste0(name, ".csv")))
sizes <- c("Solo", "2-3", "4-5", "6-10", "11-19", "20-30", "31-50", "51-100", "101+")
contrasts <- read_output("contrasts") %>% mutate(size = factor(size, levels = sizes), significant = p.value < .05)
annual <- read_output("annual_profiles") %>% mutate(size = factor(size, levels = sizes), significant = p.value < .05)
coefficients <- read_output("coefficients")
theme_paper <- theme_classic(base_size = 12) + theme(
  plot.title = element_text(face = "bold", size = 15), plot.subtitle = element_text(size = 11),
  axis.title = element_text(face = "bold"), legend.position = "bottom",
  strip.background = element_rect(fill = "white", color = "black"), strip.text = element_text(face = "bold"),
  axis.text.x = element_text(angle = 35, hjust = 1))
shape_scale <- function(es) scale_shape_manual(values = c(`FALSE` = 1, `TRUE` = 16),
  labels = if (es) c(`FALSE` = "No significativo", `TRUE` = "Significativo al 5%") else
    c(`FALSE` = "Not significant", `TRUE` = "Significant at 5%"), name = NULL)
group_names <- function(es) c(Formal = if (es) "Formales" else "Formal", Informal = if (es) "Informales" else "Informal")
group_factor <- function(x, es) factor(group_names(es)[x], levels = unname(group_names(es)))
save_plot <- function(p, name, lang, width = 11, height = 6) {
  ggsave(file.path(paper, "Paper/figures", paste0(name, "_", lang, ".png")), p,
    width = width, height = height, dpi = 300, bg = "white")
}
for (lang in c("en", "es")) {
  es <- lang == "es"
  xlab <- if (es) "Tama\u00f1o de empresa" else "Firm size"
  ylab <- if (es) "Premium salarial (%)" else "Wage premium (%)"
  ci_note <- if (es) "Intervalos de confianza del 95%, inferencia t por conglomerados" else "95% confidence intervals, cluster-based t inference"
  pdat <- contrasts %>% filter(model == "common4", reference == "Solo")
  p <- ggplot(pdat, aes(size, premium, group = 1)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = .14, color = "gray35") +
    geom_point(aes(shape = significant), color = "darkblue", size = 3.2) +
    geom_label(aes(label = sprintf("%.1f%%", premium)), fill = "black", color = "white", size = 3.4, vjust = -1) +
    scale_y_continuous(labels = label_percent(scale = 1), expand = expansion(mult = c(.05, .18))) + shape_scale(es) +
    labs(title = if (es) "Premium salarial com\u00fan por tama\u00f1o de empresa" else "Common firm-size wage premium",
      subtitle = ci_note, x = xlab, y = ylab) + theme_paper
  save_plot(p, "fig57", lang, 10, 6)
  pdat <- contrasts %>% filter(model == "simple", reference == "Solo", parameter %in% c("formal", "informal")) %>%
    mutate(group = group_factor(ifelse(parameter == "formal", "Formal", "Informal"), es))
  p <- ggplot(pdat, aes(size, premium, group = group)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = .12, color = "gray35") +
    geom_line(color = "darkblue", linewidth = .7) + geom_point(aes(shape = significant), color = "darkblue", size = 2.8) +
    geom_label(aes(label = sprintf("%.1f%%", premium)), fill = "black", color = "white", size = 2.8, vjust = -1.1) +
    facet_wrap(~group, nrow = 1) + shape_scale(es) +
    scale_y_continuous(labels = label_percent(scale = 1), expand = expansion(mult = c(.07, .18))) +
    labs(title = if (es) "Premium por tama\u00f1o y formalidad: modelo sector-a\u00f1o" else "Firm-size premiums by formality: sector-year model",
      subtitle = if (es) paste("Referencia: trabajadores solos del mismo grupo.", ci_note) else paste("Relative to solo workers of the same status.", ci_note),
      x = xlab, y = ylab) + theme_paper
  save_plot(p, "fig74", lang, 12, 6)
  pdat <- annual %>% filter(group == "Common")
  p <- ggplot(pdat, aes(year, premium)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "darkblue", alpha = .12) +
    geom_line(color = "darkblue", linewidth = .7) + geom_point(aes(shape = significant), color = "darkblue", size = 1.8) +
    facet_wrap(~size, ncol = 4) + shape_scale(es) +
    scale_x_continuous(breaks = c(2008, 2013, 2019, 2025)) +
    scale_y_continuous(labels = label_percent(scale = 1)) +
    labs(title = if (es) "Evoluci\u00f3n del premium salarial com\u00fan" else "Common firm-size wage premiums over time",
      subtitle = ci_note, x = if (es) "A\u00f1o" else "Year", y = ylab) + theme_paper
  save_plot(p, "fig59", lang, 12, 7)
  pdat <- annual %>% filter(group != "Common", year %in% c(2008, 2025)) %>%
    mutate(group = group_factor(group, es), year = factor(year))
  dodge <- position_dodge(width = .25)
  p <- ggplot(pdat, aes(size, premium, color = year, linetype = year, group = year)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = .10, alpha = .65, position = dodge) +
    geom_line(linewidth = .8, position = dodge) + geom_point(aes(shape = year), size = 2.6, position = dodge) +
    facet_wrap(~group, nrow = 1) +
    scale_color_manual(values = c(`2008` = "#D95F02", `2025` = "#0072B2")) +
    scale_linetype_manual(values = c(`2008` = "dashed", `2025` = "solid")) +
    scale_shape_manual(values = c(`2008` = 1, `2025` = 16)) +
    scale_y_continuous(labels = label_percent(scale = 1)) +
    labs(title = if (es) "Premium ajustado por tama\u00f1o y formalidad, 2008 y 2025" else "Adjusted firm-size premiums by formality, 2008 and 2025",
      subtitle = ci_note, x = xlab, y = ylab, color = NULL, linetype = NULL, shape = NULL) + theme_paper
  save_plot(p, "fig76", lang, 12, 6)
  pdat <- annual %>% filter(group != "Common", size == "101+") %>% mutate(group = group_factor(group, es))
  p <- ggplot(pdat, aes(year, premium)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "darkblue", alpha = .12) +
    geom_line(color = "darkblue", linewidth = .8) + geom_point(aes(shape = significant), color = "darkblue", size = 2.6) +
    facet_wrap(~group, nrow = 1) + shape_scale(es) +
    scale_x_continuous(breaks = c(2008, 2013, 2019, 2025)) +
    scale_y_continuous(labels = label_percent(scale = 1)) +
    labs(title = if (es) "Premium de 101+ frente a solos, por formalidad" else "101+/solo premiums by formality over time",
      subtitle = ci_note, x = if (es) "A\u00f1o" else "Year", y = ylab) + theme_paper
  save_plot(p, "fig75", lang, 11, 6)
  curves <- bind_rows(lapply(c("full", "formal", "informal"), function(s) {
    b <- coefficients %>% filter(model == paste0("polynomial_", s))
    x <- exp(seq(0, log(150), length.out = 200))
    data.frame(sample = s, assigned_size = x, premium = 100*expm1(
      b$estimate[b$term == "log_size_midpoint"]*log(x) + b$estimate[b$term == "log_size_midpoint_sq"]*log(x)^2))
  }))
  points <- bind_rows(
    contrasts %>% filter(model == "common4", reference == "Solo") %>% mutate(sample = "full"),
    contrasts %>% filter(model == "simple", reference == "Solo", parameter %in% c("formal", "informal")) %>% mutate(sample = parameter)
  ) %>% mutate(assigned_size = c(1, 2.5, 4.5, 8, 15, 25, 40.5, 75.5, 150)[as.integer(size)]) %>%
    select(sample, assigned_size, premium) %>% bind_rows(data.frame(sample = c("full", "formal", "informal"), assigned_size = 1, premium = 0))
  annotate <- function(x) x %>% mutate(
    panel = ifelse(sample == "full", if (es) "Muestra completa" else "Full sample", if (es) "Por formalidad" else "By formality"),
    series = factor(sample, levels = c("full", "formal", "informal"), labels = if (es) c("Muestra completa", "Formal", "Informal") else c("Full sample", "Formal", "Informal")))
  curves <- annotate(curves); points <- annotate(points)
  curves$panel <- factor(curves$panel, levels = unique(curves$panel))
  points$panel <- factor(points$panel, levels = levels(curves$panel))
  p <- ggplot() + geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_line(data = curves, aes(assigned_size, premium, color = series, linetype = series), linewidth = .9) +
    geom_point(data = points, aes(assigned_size, premium, color = series, shape = series), size = 2.6) +
    facet_wrap(~panel, nrow = 1, scales = "free_y") +
    scale_color_manual(values = c("#1F5EA8", "#0072B2", "#D95F02")) +
    scale_linetype_manual(values = c("solid", "solid", "dashed")) + scale_shape_manual(values = c(16, 16, 1)) +
    scale_x_log10(breaks = c(1, 2.5, 8, 25, 75.5, 150), labels = c("Solo", "2.5", "8", "25", "75.5", "150")) +
    scale_y_continuous(labels = label_percent(scale = 1)) +
    labs(title = if (es) "Aproximaci\u00f3n polin\u00f3mica al perfil salarial" else "Polynomial approximation to the firm-size wage profile",
      subtitle = if (es) "L\u00edneas: funciones cuadr\u00e1ticas. Puntos: estimaciones categ\u00f3ricas con controles sector-a\u00f1o" else
        "Lines: quadratic functions. Points: categorical estimates with sector-year controls",
      x = if (es) "Tama\u00f1o asignado de empresa, escala logar\u00edtmica" else "Assigned firm size, log scale",
      y = ylab, color = NULL, linetype = NULL, shape = NULL) + theme_paper
  save_plot(p, "fig78", lang, 11, 6)
}
