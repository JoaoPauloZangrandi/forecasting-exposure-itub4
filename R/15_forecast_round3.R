# =============================================================================
# 15_forecast_round3.R — onde existe previsibilidade? (exploração barata, R)
# Rodadas 1-2: a VARIAÇÃO mensal é ~martingale. Aqui testamos:
#   (1) prever o NÍVEL (posição US$ e PESO), não a variação;
#   (2) horizontes h = 1, 3, 6 meses (reversão à média aparece em prazos longos);
#   (3) AR(1) de PAINEL com reversão à média da própria gestora (rho comum).
# Benchmark: random walk no nível (y_hat_{t+h} = y_t). Skill = % de RMSE abaixo do RW.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")
MIN_TRAIN <- 36L

panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
mat <- function(col) {
  w <- dcast(panel, data ~ gestora, value.var = col); setorder(w, data)
  M <- as.matrix(w[, -1]); M[, colSums(is.na(M)) == 0, drop = FALSE]
}
TARGS <- list(pos_usd = mat("pos_usd_mil"), peso = mat("peso_itub4"))

ar_h <- function(x, h) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) return(rep(mean(x), h)[h])
  as.numeric(predict(fit, n.ahead = h)$pred)[h]
}

eval_target <- function(M, h) {
  Tn <- nrow(M); G <- ncol(M); out <- list()
  for (t in MIN_TRAIN:(Tn - h)) {
    train <- M[1:t, , drop = FALSE]; actual <- M[t + h, ]
    mu <- colMeans(train)
    # rho de painel (AR1 nos desvios da media), comum a todas as gestoras
    D <- sweep(train, 2, mu); Dlag <- D[-t, , drop = FALSE]; Dnow <- D[-1, , drop = FALSE]
    rho <- sum(Dlag * Dnow, na.rm = TRUE) / sum(Dlag^2, na.rm = TRUE)
    rho <- max(min(rho, 1), -1)
    fc <- list(RW = M[t, ],
               AR_indiv = vapply(seq_len(G), function(j) ar_h(train[, j], h), numeric(1)),
               AR1_painel = mu + rho^h * (M[t, ] - mu))
    for (m in names(fc))
      out[[length(out) + 1L]] <- data.table(h = h, model = m, actual = actual, forecast = fc[[m]])
  }
  rbindlist(out)
}

res <- rbindlist(lapply(names(TARGS), function(tg)
  rbindlist(lapply(c(1L, 3L, 6L), function(h) eval_target(TARGS[[tg]], h)[, target := tg]))))
res[, se := (actual - forecast)^2]

met <- res[, .(RMSE = sqrt(mean(se))), by = .(target, h, model)]
rw  <- met[model == "RW", .(target, h, rmse_rw = RMSE)]
met <- merge(met, rw, by = c("target", "h"))
met[, skill_pct := round(100 * (1 - RMSE / rmse_rw), 1)]
tab <- dcast(met[model != "RW"], target + h ~ model, value.var = "skill_pct")
write_tab(met, "forecast_round3_metrics.csv")
cat("\n== RODADA 3: skill (% RMSE abaixo do RW no nivel), por alvo e horizonte ==\n")
print(tab)
cat("\n(positivo = bate o random walk; rho de painel <1 indica reversao a media)\n")

p <- ggplot(met[model != "RW"], aes(factor(h), skill_pct, fill = model)) +
  geom_col(position = "dodge") + geom_hline(yintercept = 0, linetype = "dashed") +
  facet_wrap(~target, scales = "free_y") +
  labs(title = "Skill vs Random Walk no nivel, por horizonte (ITUB4)",
       x = "horizonte (meses)", y = "% RMSE abaixo do RW", fill = NULL) +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(OUT_FIG, "forecast_round3_skill.png"), p, width = 9, height = 5, dpi = 150)
cat("\nOK - forecast_round3_metrics.csv e figura salvos.\n")
