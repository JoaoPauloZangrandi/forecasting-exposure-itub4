# =============================================================================
# 19_half_life.R — REFINAMENTO: modela a "alocação-alvo" e a velocidade de
# reversão à média. AR(1) no nível da posição (ITUB4): y_t = c + rho*y_{t-1}.
# rho<1 => reverte; meia-vida = ln(0.5)/ln(rho) meses (tempo p/ fechar metade do
# desvio em relacao ao alvo mu_g = c/(1-rho)). Reporta valor em US$, quantidade
# estimada de ações (proxy de demanda) e peso.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")

panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
mat <- function(col) {
  w <- dcast(panel, data ~ gestora, value.var = col); setorder(w, data)
  M <- as.matrix(w[, -1]); M[, colSums(is.na(M)) == 0, drop = FALSE]
}

ar1 <- function(x) {                                  # rho e meia-vida do AR(1)
  n <- length(x); fit <- lm(x[-1] ~ x[-n]); rho <- unname(coef(fit)[2])
  hl <- if (is.finite(rho) && rho > 0 && rho < 1) log(0.5) / log(rho) else NA_real_
  c(rho = rho, half_life = hl, mu = unname(coef(fit)[1]) / (1 - rho))
}

half_life_tab <- function(M, alvo) {
  r <- rbindlist(lapply(colnames(M), function(g) {
    a <- ar1(M[, g]); data.table(alvo = alvo, gestora = g, rho = round(a["rho"], 3),
                                 half_life_meses = round(a["half_life"], 1), mu = round(a["mu"]))
  }))
  # pooled (painel, desvios da media; rho comum)
  mu <- colMeans(M); D <- sweep(M, 2, mu)
  Dl <- D[-nrow(D), ]; Dn <- D[-1, ]
  rho_p <- sum(Dl * Dn) / sum(Dl^2)
  hl_p <- if (rho_p > 0 && rho_p < 1) log(0.5) / log(rho_p) else NA_real_
  list(tab = r, rho_pool = rho_p, hl_pool = hl_p)
}

pos <- half_life_tab(mat("pos_usd_mil"), "pos_usd")
qtd <- half_life_tab(mat("qtd_itub4"), "qtd_itub4")
pes <- half_life_tab(mat("peso_itub4"), "peso")
write_tab(rbind(pos$tab, qtd$tab, pes$tab), "half_life_by_gestora.csv")

cat("== REVERSAO A MEDIA (meia-vida em meses) ==\n")
rev <- pos$tab[is.finite(half_life_meses)]
cat(sprintf("POSICAO US$: %d/%d gestoras revertem (0<rho<1) | rho mediano %.2f | meia-vida mediana %.1f meses\n",
            nrow(rev), nrow(pos$tab), median(rev$rho), median(rev$half_life_meses)))
cat(sprintf("  POOLED (painel): rho=%.3f -> meia-vida %.1f meses\n", pos$rho_pool, pos$hl_pool))
qtdr <- qtd$tab[is.finite(half_life_meses)]
cat(sprintf("QUANTIDADE: %d/%d gestoras revertem | rho mediano %.2f | meia-vida mediana %.1f meses\n",
            nrow(qtdr), nrow(qtd$tab), median(qtdr$rho), median(qtdr$half_life_meses)))
cat(sprintf("  POOLED (painel): rho=%.3f -> meia-vida %.1f meses\n", qtd$rho_pool, qtd$hl_pool))
pesr <- pes$tab[is.finite(half_life_meses)]
cat(sprintf("PESO: %d/%d revertem | POOLED rho=%.3f (proximo de 1 => ~random walk, sem reversao)\n",
            nrow(pesr), nrow(pes$tab), pes$rho_pool))
cat("\nGestoras com reversao mais RAPIDA (posicao US$):\n")
print(head(rev[order(half_life_meses), .(gestora, rho, half_life_meses, mu_usd_mil = mu)], 8))
cat("\nMais LENTA / persistente:\n")
print(head(rev[order(-half_life_meses), .(gestora, rho, half_life_meses)], 5))

p <- ggplot(rev, aes(half_life_meses)) +
  geom_histogram(binwidth = 1, fill = "#2f6f8f", color = "white") +
  geom_vline(xintercept = median(rev$half_life_meses), color = "#8f3f2f", linewidth = 0.8) +
  labs(title = "Meia-vida da reversao a alocacao-alvo em ITUB4 (por gestora)",
       subtitle = "linha vermelha = mediana", x = "meses para fechar metade do desvio", y = "nº de gestoras") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT_FIG, "half_life_hist.png"), p, width = 8, height = 5, dpi = 150)

pq <- ggplot(qtdr, aes(half_life_meses)) +
  geom_histogram(binwidth = 1, fill = "#426f54", color = "white") +
  geom_vline(xintercept = median(qtdr$half_life_meses), color = "#8f3f2f", linewidth = 0.8) +
  labs(title = "Meia-vida da reversao da quantidade estimada de ITUB4",
       subtitle = "linha vermelha = mediana", x = "meses para fechar metade do desvio", y = "nº de gestoras") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT_FIG, "half_life_quantity_hist.png"), pq, width = 8, height = 5, dpi = 150)
cat("\nOK - half_life_by_gestora.csv e figura salvos.\n")
