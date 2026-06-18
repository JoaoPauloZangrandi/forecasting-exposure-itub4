# =============================================================================
# 20_forecast_quantity.R — forecasting usando QUANTIDADE estimada de ITUB4.
# A CONS não informa número de ações; estimamos:
#   qtd_itub4 = valor_net_mil * 1000 / fechamento_B3_ITUB4.
# Esta é a especificação mais próxima de demanda: separa mudança de preço de
# mudança aproximada na quantidade carregada pelas gestoras.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")
set.seed(1)
MIN_TRAIN <- 36L

panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))

make_matrix <- function(col, drop_first = FALSE) {
  w <- dcast(panel, data ~ gestora, value.var = col)
  setorder(w, data)
  M <- as.matrix(w[, -1])
  rownames(M) <- as.character(w$data)
  if (drop_first) M <- M[-1, , drop = FALSE]
  M[, colSums(is.na(M)) == 0, drop = FALSE]
}

ar_forecast <- function(x) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) return(mean(x))
  as.numeric(predict(fit, n.ahead = 1)$pred)
}

pca_forecast <- function(train, k) {
  t <- nrow(train); mu <- colMeans(train)
  sdv <- apply(train, 2, sd); sdv[!is.finite(sdv) | sdv == 0] <- 1
  pc <- prcomp(scale(train, mu, sdv), center = FALSE, scale. = FALSE)
  k <- min(k, ncol(pc$x))
  Fs <- pc$x[, 1:k, drop = FALSE]
  vapply(seq_len(ncol(train)), function(j) {
    df <- data.frame(y = train[2:t, j], Fs[1:(t - 1), , drop = FALSE])
    nx <- as.data.frame(Fs[t, , drop = FALSE]); names(nx) <- names(df)[-1]
    as.numeric(predict(lm(y ~ ., data = df), nx))
  }, numeric(1))
}

eval_delta_qtd <- function() {
  M <- make_matrix("delta_qtd_itub4", drop_first = TRUE)
  Tn <- nrow(M); G <- ncol(M)
  log_msg("Matriz delta quantidade: %d meses x %d gestoras", Tn, G)

  rows <- list()
  for (t in MIN_TRAIN:(Tn - 1)) {
    train <- M[1:t, , drop = FALSE]; actual <- M[t + 1, ]
    ar <- vapply(seq_len(G), function(j) ar_forecast(train[, j]), numeric(1))
    fc <- list(RW = rep(0, G), AR = ar, AR_encolhido = 0.5 * ar,
               PCA1 = pca_forecast(train, 1), PCA2 = pca_forecast(train, 2),
               PCA3 = pca_forecast(train, 3))
    for (m in names(fc))
      rows[[length(rows) + 1L]] <- data.table(origin = t, gestora = colnames(M),
                                              model = m, actual = actual, forecast = fc[[m]])
  }
  res <- rbindlist(rows)
  res[, `:=`(se = (actual - forecast)^2, ae = abs(actual - forecast))]
  rmse_rw <- res[model == "RW", sqrt(mean(se))]
  mae_rw  <- res[model == "RW", mean(ae)]
  met <- res[, .(RMSE_acoes = sqrt(mean(se)), MAE_acoes = mean(ae),
                 dir_hit = {ok <- actual != 0; round(100 * mean(sign(forecast[ok]) == sign(actual[ok])), 1)}),
             by = model]
  met[, `:=`(RMSE_mi_acoes = RMSE_acoes / 1e6,
             MAE_mi_acoes = MAE_acoes / 1e6,
             skill_RMSE = round(100 * (1 - RMSE_acoes / rmse_rw), 1),
             skill_MAE  = round(100 * (1 - MAE_acoes / mae_rw), 1))]
  met[model == "RW", dir_hit := NA_real_]
  setorder(met, -skill_RMSE)
  write_tab(met, "forecast_quantity_delta_metrics.csv")

  p <- ggplot(met, aes(reorder(model, skill_RMSE), skill_RMSE)) +
    geom_col(fill = "#2f6f8f") + geom_hline(yintercept = 0, linetype = "dashed") +
    coord_flip() +
    labs(title = "Delta da quantidade estimada de ITUB4: skill vs Random Walk",
         x = NULL, y = "% RMSE abaixo do RW") +
    theme_minimal(base_size = 11)
  ggsave(file.path(OUT_FIG, "forecast_quantity_delta_skill.png"), p, width = 8, height = 5, dpi = 150)
  met
}

ar_h <- function(x, h) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) return(rep(mean(x), h)[h])
  as.numeric(predict(fit, n.ahead = h)$pred)[h]
}

eval_level_qtd <- function() {
  M <- make_matrix("qtd_itub4")
  Tn <- nrow(M); G <- ncol(M)
  log_msg("Matriz nivel quantidade: %d meses x %d gestoras", Tn, G)

  out <- list()
  for (h in c(1L, 3L, 6L)) {
    for (t in MIN_TRAIN:(Tn - h)) {
      train <- M[1:t, , drop = FALSE]; actual <- M[t + h, ]
      mu <- colMeans(train)
      D <- sweep(train, 2, mu); Dlag <- D[-t, , drop = FALSE]; Dnow <- D[-1, , drop = FALSE]
      rho <- sum(Dlag * Dnow, na.rm = TRUE) / sum(Dlag^2, na.rm = TRUE)
      rho <- max(min(rho, 1), -1)
      fc <- list(RW = M[t, ],
                 AR_indiv = vapply(seq_len(G), function(j) ar_h(train[, j], h), numeric(1)),
                 AR1_painel = mu + rho^h * (M[t, ] - mu))
      for (m in names(fc))
        out[[length(out) + 1L]] <- data.table(h = h, model = m, actual = actual, forecast = fc[[m]])
    }
  }
  res <- rbindlist(out)
  res[, se := (actual - forecast)^2]
  met <- res[, .(RMSE_acoes = sqrt(mean(se))), by = .(h, model)]
  rw  <- met[model == "RW", .(h, rmse_rw = RMSE_acoes)]
  met <- merge(met, rw, by = "h")
  met[, `:=`(RMSE_mi_acoes = RMSE_acoes / 1e6,
             skill_pct = round(100 * (1 - RMSE_acoes / rmse_rw), 1))]
  setorder(met, h, -skill_pct)
  write_tab(met, "forecast_quantity_level_metrics.csv")

  p <- ggplot(met[model != "RW"], aes(factor(h), skill_pct, fill = model)) +
    geom_col(position = "dodge") + geom_hline(yintercept = 0, linetype = "dashed") +
    labs(title = "Nivel da quantidade estimada de ITUB4: skill vs Random Walk",
         x = "horizonte (meses)", y = "% RMSE abaixo do RW", fill = NULL) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")
  ggsave(file.path(OUT_FIG, "forecast_quantity_level_skill.png"), p, width = 8, height = 5, dpi = 150)
  met
}

delta_met <- eval_delta_qtd()
level_met <- eval_level_qtd()

cat("\n== QUANTIDADE: delta mensal (acoes, em milhoes no RMSE) ==\n")
print(delta_met[, .(model, RMSE_mi_acoes = round(RMSE_mi_acoes, 2),
                    skill_RMSE, skill_MAE, dir_hit)])
cat("\n== QUANTIDADE: nivel (skill vs RW) ==\n")
print(dcast(level_met[model != "RW"], h ~ model, value.var = "skill_pct"))
cat("\nOK - resultados de quantidade salvos.\n")
