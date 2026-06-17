# =============================================================================
# 14_forecast_round2.R — REFINAMENTOS sobre a rodada 1 (ITUB4, delta pos US$).
# A rodada 1 mostrou: ninguem bate o RW e o PCA(k=3) superajusta. Aqui:
#   (a) REGULARIZACAO: PCA com menos fatores (k=1,2) deve superajustar menos;
#   (b) COMBINACAO/ENCOLHIMENTO: encolher o AR em direcao ao RW (0);
#   (c) ROBUSTEZ: reportar skill em MAE (menos sensivel a outliers que RMSE);
#   (d) DIRECAO: acerto de SINAL (sobe/desce) - alvo mais alcancavel que magnitude.
# Mesmo harness OOS de origem movel, 1 passo, sem vazamento.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")
set.seed(1)
MIN_TRAIN <- 36L

panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
w <- dcast(panel, data ~ gestora, value.var = "delta_pos_usd_mil"); setorder(w, data)
M <- as.matrix(w[, -1])[-1, , drop = FALSE]
M <- M[, colSums(is.na(M)) == 0, drop = FALSE]
Tn <- nrow(M); G <- ncol(M)
log_msg("Matriz: %d meses x %d gestoras", Tn, G)

ar_forecast <- function(x) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) mean(x) else as.numeric(predict(fit, n.ahead = 1)$pred)
}
pca_forecast <- function(train, k) {
  t <- nrow(train); mu <- colMeans(train)
  sdv <- apply(train, 2, sd); sdv[!is.finite(sdv) | sdv == 0] <- 1
  pc <- prcomp(scale(train, mu, sdv), center = FALSE, scale. = FALSE)
  k <- min(k, ncol(pc$x)); Fs <- pc$x[, 1:k, drop = FALSE]
  vapply(seq_len(ncol(train)), function(j) {
    df <- data.frame(y = train[2:t, j], Fs[1:(t - 1), , drop = FALSE])
    nx <- as.data.frame(Fs[t, , drop = FALSE]); names(nx) <- names(df)[-1]
    as.numeric(predict(lm(y ~ ., data = df), nx))
  }, numeric(1))
}

rows <- list()
for (t in MIN_TRAIN:(Tn - 1)) {
  train <- M[1:t, , drop = FALSE]; actual <- M[t + 1, ]
  ar <- vapply(seq_len(G), function(j) ar_forecast(train[, j]), numeric(1))
  fc <- list(RW = rep(0, G), AR = ar, AR_encolhido = 0.5 * ar,
             PCA1 = pca_forecast(train, 1), PCA2 = pca_forecast(train, 2), PCA3 = pca_forecast(train, 3))
  for (m in names(fc))
    rows[[length(rows) + 1L]] <- data.table(origin = t, gestora = colnames(M),
                                            model = m, actual = actual, forecast = fc[[m]])
}
res <- rbindlist(rows)
res[, `:=`(se = (actual - forecast)^2, ae = abs(actual - forecast))]

rmse_rw <- res[model == "RW", sqrt(mean(se))]
mae_rw  <- res[model == "RW", mean(ae)]
met <- res[, .(RMSE = sqrt(mean(se)), MAE = mean(ae),
               # acerto de direcao (exclui actual == 0)
               dir_hit = {ok <- actual != 0; round(100 * mean(sign(forecast[ok]) == sign(actual[ok])), 1)}),
           by = model]
met[, `:=`(skill_RMSE = round(100 * (1 - RMSE / rmse_rw), 1),
           skill_MAE  = round(100 * (1 - MAE / mae_rw), 1))]
setorder(met, -skill_MAE)
write_tab(met, "forecast_round2_metrics.csv")
cat("\n== RODADA 2: metricas OOS (alvo delta_pos_usd; mil USD) ==\n")
print(met[, .(model, RMSE = round(RMSE), MAE = round(MAE), skill_RMSE, skill_MAE, dir_hit)])

# teste binomial da direcao para o melhor modelo de direcao (vs 50%)
bm <- met[model != "RW"][which.max(dir_hit), model]
ok <- res[model == bm & actual != 0]
ht <- ok[, sum(sign(forecast) == sign(actual))]; nn <- nrow(ok)
pb <- binom.test(ht, nn, 0.5)$p.value
cat(sprintf("\nMelhor em direcao: %s -> %d/%d (%.1f%%), p(binom vs 50%%)=%.4f\n",
            bm, ht, nn, 100 * ht / nn, pb))

p <- ggplot(met, aes(reorder(model, skill_MAE), skill_MAE)) +
  geom_col(fill = "#2f6f8f") + geom_hline(yintercept = 0, linetype = "dashed") + coord_flip() +
  labs(title = "Skill vs Random Walk (MAE) - rodada 2", x = NULL, y = "% melhora sobre RW (MAE)") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT_FIG, "forecast_round2_skill.png"), p, width = 8, height = 5, dpi = 150)
cat("\nOK - forecast_round2_metrics.csv e figura salvos.\n")
