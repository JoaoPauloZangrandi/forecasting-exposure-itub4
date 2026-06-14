# =============================================================================
# 07_correlation.R — matrizes de correlação entre gestoras (variação mensal da
# posição em US$) + figuras. O orientador pediu explicitamente estas matrizes.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

build_correlations <- function(panel) {
  validas <- panel[is.finite(delta_pos_usd_mil),
                   .(n = .N, s = sd(delta_pos_usd_mil, na.rm = TRUE)),
                   by = gestora][n >= 2 & is.finite(s) & s > 0]
  if (nrow(validas) < 2L) { warning("Poucas gestoras para correlacao."); return(invisible(NULL)) }

  sub <- panel[gestora %in% validas$gestora & is.finite(delta_pos_usd_mil),
               .(data, gestora, delta_pos_usd_mil)]
  w <- dcast(sub, data ~ gestora, value.var = "delta_pos_usd_mil")
  m <- as.matrix(w[, -1, with = FALSE]); rownames(m) <- as.character(w$data)

  cor_pw <- cor(m, use = "pairwise.complete.obs")
  n_pw   <- crossprod(!is.na(m))
  write_matrix(cor_pw, "cor_gestoras_delta_usd_pairwise.csv")
  write_matrix(n_pw,   "cor_gestoras_delta_usd_n.csv")

  cor_dt <- as.data.table(as.table(cor_pw)); setnames(cor_dt, c("g1", "g2", "corr"))
  p <- ggplot(cor_dt, aes(g1, g2, fill = corr)) +
    geom_tile(color = "white", linewidth = 0.2) + coord_equal() +
    scale_fill_gradient2(low = "#b2182b", mid = "white", high = "#2166ac",
                         midpoint = 0, limits = c(-1, 1), na.value = "grey90") +
    labs(title = "Correlacao entre gestoras: variacao mensal da posicao em ITUB4 (US$)",
         x = NULL, y = NULL, fill = "corr") +
    theme_minimal(base_size = 8) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(OUT_FIG, "correlation_heatmap_delta_usd.png"), p,
         width = 9, height = 8, dpi = 150)
  invisible(cor_pw)
}

plot_positions <- function(panel, top_n = 8L) {
  top <- panel[, .(m = mean(pos_usd_mil, na.rm = TRUE)), by = gestora][order(-m)][seq_len(min(top_n, .N)), gestora]
  p <- ggplot(panel[gestora %in% top], aes(data, pos_usd_mil / 1e3, color = gestora)) +
    geom_line(linewidth = 0.7, na.rm = TRUE) +
    labs(title = "Posicao em ITUB4 por gestora (US$ milhoes, exposicao net)",
         x = NULL, y = "US$ milhoes", color = "Gestora") +
    theme_minimal(base_size = 10) + theme(legend.position = "bottom")
  ggsave(file.path(OUT_FIG, "pos_usd_top_gestoras.png"), p, width = 10, height = 6, dpi = 150)
  invisible(top)
}
