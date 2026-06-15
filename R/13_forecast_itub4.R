# =============================================================================
# 13_forecast_itub4.R — PRIMEIRA RODADA de forecasting (ITUB4).
# Alvo: y_{g,t} = delta_pos_usd_mil (variação mensal da posição em US$) por gestora.
# Avaliação: origem móvel (janela expansível), 1 passo à frente, OOS, SEM vazamento
# (PCA/parâmetros estimados só no treino). Modelos: random walk, média, AR(p),
# fator-aumentado por PCA (Stock-Watson). GNN fica para a próxima rodada.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")
set.seed(1)

K_FACT  <- 3L     # nº de fatores PCA
MIN_TRAIN <- 36L  # origem inicial (meses de treino)

# --- matriz balanceada meses x gestoras de delta_pos_usd ---
panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
w <- dcast(panel, data ~ gestora, value.var = "delta_pos_usd_mil")
setorder(w, data)
M <- as.matrix(w[, -1]); rownames(M) <- as.character(w$data)
M <- M[-1, , drop = FALSE]                       # 1ª linha não tem delta
keep <- colSums(is.na(M)) == 0                   # gestoras com histórico completo
M <- M[, keep, drop = FALSE]
Tn <- nrow(M); G <- ncol(M)
log_msg("Matriz de previsao: %d meses x %d gestoras (cobertura completa)", Tn, G)

# --- previsão fator-aumentada por PCA (sem vazamento: PCA no treino) ---
pca_forecast <- function(train, k) {
  t <- nrow(train); mu <- colMeans(train)
  sdv <- apply(train, 2, sd); sdv[!is.finite(sdv) | sdv == 0] <- 1
  Z <- scale(train, center = mu, scale = sdv)
  pc <- prcomp(Z, center = FALSE, scale. = FALSE)
  k <- min(k, ncol(pc$x))
  Fs <- pc$x[, 1:k, drop = FALSE]                 # scores t x k
  fhat <- numeric(ncol(train))
  for (j in seq_len(ncol(train))) {
    df <- data.frame(y = train[2:t, j], Fs[1:(t - 1), , drop = FALSE])
    fit <- lm(y ~ ., data = df)
    nx <- as.data.frame(Fs[t, , drop = FALSE]); names(nx) <- names(df)[-1]
    fhat[j] <- predict(fit, nx)
  }
  fhat
}

ar_forecast <- function(x) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) return(mean(x))
  as.numeric(predict(fit, n.ahead = 1)$pred)
}

# --- loop de origem móvel ---
rows <- list()
for (t in MIN_TRAIN:(Tn - 1)) {
  train <- M[1:t, , drop = FALSE]; actual <- M[t + 1, ]
  fc <- list(RW = rep(0, G), Media = colMeans(train),
             AR = vapply(seq_len(G), function(j) ar_forecast(train[, j]), numeric(1)),
             PCA = pca_forecast(train, K_FACT))
  for (m in names(fc))
    rows[[length(rows) + 1L]] <- data.table(origin = t, gestora = colnames(M),
                                            model = m, actual = actual, forecast = fc[[m]])
}
res <- rbindlist(rows)
res[, `:=`(err = actual - forecast, se = (actual - forecast)^2, ae = abs(actual - forecast))]

# --- métricas ---
met <- res[, .(RMSE = sqrt(mean(se)), MAE = mean(ae)), by = model]
rmse_rw <- met[model == "RW", RMSE]
met[, skill_vs_RW_pct := round(100 * (1 - RMSE / rmse_rw), 1)]
# teste pareado (SE do modelo vs RW), por origem-gestora
se_rw <- res[model == "RW", .(origin, gestora, se_rw = se)]
met[, dm_p := vapply(model, function(m) {
  if (m == "RW") return(NA_real_)
  d <- merge(res[model == m, .(origin, gestora, se)], se_rw, by = c("origin", "gestora"))
  tryCatch(t.test(d$se, d$se_rw, paired = TRUE)$p.value, error = function(e) NA_real_)
}, numeric(1))]
setorder(met, RMSE)
write_tab(met, "forecast_metrics.csv")
cat("\n== METRICAS OOS (1 passo, origem movel; alvo delta_pos_usd em mil USD) ==\n"); print(met)

best <- met[model != "RW"][1, model]
by_g <- res[model %in% c("RW", best), .(RMSE = sqrt(mean(se))), by = .(gestora, model)]
by_g <- dcast(by_g, gestora ~ model, value.var = "RMSE")
by_g[, ganho_pct := round(100 * (1 - get(best) / RW), 1)]
setorder(by_g, -ganho_pct)
write_tab(by_g, "forecast_rmse_by_gestora.csv")
cat(sprintf("\nMelhor modelo: %s. Gestoras com maior ganho vs RW:\n", best))
print(head(by_g, 8))

# --- figuras ---
p1 <- ggplot(met, aes(reorder(model, RMSE), RMSE)) + geom_col(fill = "#2f6f8f") +
  labs(title = "RMSE out-of-sample por modelo (ITUB4, delta posicao US$)", x = NULL, y = "RMSE (mil USD)") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT_FIG, "forecast_rmse_by_model.png"), p1, width = 8, height = 5, dpi = 150)

gx <- if ("Itaú" %in% colnames(M)) "Itaú" else colnames(M)[which.max(colMeans(abs(M)))]
cmp <- res[gestora == gx & model %in% c("RW", best)]
cmp <- rbind(cmp[model == best, .(origin, serie = "previsto", v = forecast)],
             cmp[model == best, .(origin, serie = "real", v = actual)])
p2 <- ggplot(cmp, aes(origin, v / 1e3, color = serie)) + geom_line(linewidth = 0.8) +
  labs(title = sprintf("%s: variacao da posicao em ITUB4 (US$ mi) - real vs previsto (%s)", gx, best),
       x = "origem (mes)", y = "US$ milhoes", color = NULL) +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(OUT_FIG, "forecast_actual_vs_pred.png"), p2, width = 10, height = 5, dpi = 150)

cat("\nOK — forecast_metrics.csv, forecast_rmse_by_gestora.csv e 2 figuras salvos.\n")
