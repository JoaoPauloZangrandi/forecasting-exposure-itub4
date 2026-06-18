# =============================================================================
# 23_forecast_consolidated_panel.R -- forecasting consolidado "publication-grade"
#
# Objetivo:
#   Prever o NIVEL da exposicao consolidada pos_usd_mil por gestora x acao.
#   A unidade e gestora x ticker x mes. O alvo e E[g,i,t+1].
#
# Modelos:
#   RW             : E[g,i,t]
#   AR1_indiv      : AR(1) individual com coeficiente de persistencia limitado
#                    a [0, 0.995], evitando extrapolacoes explosivas em series
#                    curtas/ruidosas.
#   AR1_painel     : reversao a media com coeficiente comum por acao.
#   N1_painel      : AR1_painel + exposicao do restante do mercado (-g).
#   FATOR1_painel  : AR1_painel + primeiro fator comum de exposicao da acao.
#
# Protocolo:
#   Origem movel, janela expansivel, sem vazamento. PCA/fator, medias e
#   coeficientes sao estimados apenas ate t. Benchmark central = random walk.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")

MIN_TRAIN <- 36L
MIN_MONTHS <- 24L
MIN_GEST <- 5L
set.seed(123)

panel <- fread(file.path(OUT_PROC, "painel_all_stocks.csv"))
panel[, data := as.Date(data)]
alldates <- sort(unique(panel$data))

cnt  <- panel[pos_usd_mil > 0, .(m = .N), by = .(ticker, grupo)]
elig <- cnt[m >= MIN_MONTHS]
tks  <- elig[, .(ng = .N), by = ticker][ng >= MIN_GEST, ticker]
log_msg("Acoes avaliaveis: %d (de %d no painel)", length(tks), uniqueN(panel$ticker))

clip <- function(x, lo, hi) pmin(pmax(x, lo), hi)

ar1_forecast <- function(x) {
  if (length(x) < 12 || sd(x) < 1e-10) return(tail(x, 1))
  y <- x[-1]
  z <- x[-length(x)]
  mu <- mean(x)
  den <- sum((z - mu)^2)
  if (!is.finite(den) || den < 1e-10) return(tail(x, 1))
  rho <- sum((y - mu) * (z - mu)) / den
  if (!is.finite(rho)) return(tail(x, 1))
  rho <- clip(rho, 0, 0.995)
  as.numeric(mu + rho * (tail(x, 1) - mu))
}

safe_lm_coef <- function(formula, data, names_expected) {
  fit <- tryCatch(lm(formula, data), error = function(e) NULL)
  out <- setNames(rep(0, length(names_expected)), names_expected)
  if (is.null(fit)) return(out)
  cc <- coef(fit)
  cc <- cc[is.finite(cc)]
  out[names(out) %in% names(cc)] <- cc[names(out)[names(out) %in% names(cc)]]
  out
}

eval_ticker <- function(tk) {
  gs <- elig[ticker == tk, grupo]
  sub <- panel[ticker == tk & grupo %in% gs, .(data, grupo, pos_usd_mil)]
  W <- dcast(sub, data ~ grupo, value.var = "pos_usd_mil")
  W <- merge(data.table(data = alldates), W, by = "data", all.x = TRUE)
  M <- as.matrix(W[, -1])
  M[is.na(M)] <- 0
  G <- ncol(M); Tn <- nrow(M)
  if (G < MIN_GEST || Tn <= MIN_TRAIN + 1) return(NULL)

  # Exclui tickers em que o RW tem erro zero: serie degenerada, nao informativa.
  if (sum((M[-1, ] - M[-Tn, ])^2) <= .Machine$double.eps) {
    return(list(rows = NULL, coef = data.table(ticker = tk, degenerate_rw = TRUE)))
  }

  rows <- list(); coefs <- list()
  for (t in MIN_TRAIN:(Tn - 1)) {
    train <- M[1:t, , drop = FALSE]
    actual <- M[t + 1, ]
    current <- M[t, ]
    mu <- colMeans(train)
    s <- 1:(t - 1)

    # Restante do mercado (-g) para cada gestora, na mesma acao.
    n1 <- if (G > 1) (rowSums(M) - M) / (G - 1) else M
    nb <- colMeans(n1[1:t, , drop = FALSE])

    # Fator comum estimado somente no treino.
    pc_scores <- rep(0, t)
    pc_t <- 0
    if (G >= 2 && any(apply(train, 2, sd) > 1e-8)) {
      pc <- tryCatch(prcomp(train, center = TRUE, scale. = FALSE), error = function(e) NULL)
      if (!is.null(pc) && ncol(pc$x) >= 1) {
        pc_scores <- as.numeric(pc$x[, 1])
        pc_t <- pc_scores[t]
      }
    }

    df <- data.table(
      y = as.vector(sweep(M[s + 1, , drop = FALSE], 2, mu)),
      x1 = as.vector(sweep(M[s, , drop = FALSE], 2, mu)),
      x2 = as.vector(sweep(n1[s, , drop = FALSE], 2, nb)),
      f1 = rep(pc_scores[s], times = G)
    )

    b_ar <- safe_lm_coef(y ~ x1 - 1, df, c("x1"))
    b_n1 <- safe_lm_coef(y ~ x1 + x2 - 1, df, c("x1", "x2"))
    b_f1 <- safe_lm_coef(y ~ x1 + f1 - 1, df, c("x1", "f1"))
    b_ar["x1"] <- clip(b_ar["x1"], 0, 0.995)
    b_n1["x1"] <- clip(b_n1["x1"], 0, 0.995)
    b_n1["x2"] <- clip(b_n1["x2"], -1, 1)
    b_f1["x1"] <- clip(b_f1["x1"], 0, 0.995)

    x1n <- current - mu
    x2n <- n1[t, ] - nb
    ar_indiv <- vapply(seq_len(G), function(j) ar1_forecast(train[, j]), numeric(1))

    fc <- list(
      RW = current,
      AR1_indiv = ar_indiv,
      AR1_painel = mu + b_ar["x1"] * x1n,
      N1_painel = mu + b_n1["x1"] * x1n + b_n1["x2"] * x2n,
      FATOR1_painel = mu + b_f1["x1"] * x1n + b_f1["f1"] * pc_t
    )

    for (m in names(fc)) {
      rows[[length(rows) + 1L]] <- data.table(
        ticker = tk, origin_date = W$data[t], target_date = W$data[t + 1],
        grupo = colnames(M), model = m, actual = actual, current = current,
        forecast = as.numeric(fc[[m]])
      )
    }
    coefs[[length(coefs) + 1L]] <- data.table(
      ticker = tk, origin_date = W$data[t],
      beta_ar = unname(b_ar["x1"]),
      beta_n1_own = unname(b_n1["x1"]),
      beta_n1_market = unname(b_n1["x2"]),
      beta_factor_own = unname(b_f1["x1"]),
      beta_factor = unname(b_f1["f1"]),
      degenerate_rw = FALSE
    )
  }
  list(rows = rbindlist(rows), coef = rbindlist(coefs))
}

res_list <- lapply(tks, eval_ticker)
res_list <- res_list[!vapply(res_list, is.null, logical(1))]
row_list <- lapply(res_list, `[[`, "rows")
coef_list <- lapply(res_list, `[[`, "coef")
row_list <- row_list[!vapply(row_list, is.null, logical(1))]
coef_list <- coef_list[!vapply(coef_list, is.null, logical(1))]
oos <- rbindlist(row_list, fill = TRUE)
coef_tab <- rbindlist(coef_list, fill = TRUE)

oos[, `:=`(
  err = actual - forecast,
  abs_err = abs(actual - forecast),
  se = (actual - forecast)^2,
  actual_delta = actual - current,
  forecast_delta = forecast - current
)]

rw_oos <- oos[model == "RW", .(rmse_rw_oos = sqrt(mean(se))), by = ticker]
degenerate_oos <- rw_oos[rmse_rw_oos <= .Machine$double.eps, ticker]
if (length(degenerate_oos)) {
  log_msg("Excluindo tickers degenerados no OOS (RW perfeito, skill indefinida): %s",
          paste(degenerate_oos, collapse = ", "))
  oos <- oos[!ticker %in% degenerate_oos]
  coef_tab <- coef_tab[!ticker %in% degenerate_oos]
}

metrics <- oos[, {
  idx <- abs(actual_delta) > 1e-10 & abs(forecast_delta) > 1e-10
  .(
    N = .N,
    RMSE = sqrt(mean(se)),
    MAE = mean(abs_err),
    direction_acc = if (any(idx)) mean(sign(actual_delta[idx]) == sign(forecast_delta[idx])) else NA_real_
  )
}, by = model]
rw <- metrics[model == "RW", .(RMSE_RW = RMSE, MAE_RW = MAE)]
metrics[, `:=`(
  skill_rmse_pct = round(100 * (1 - RMSE / rw$RMSE_RW), 2),
  skill_mae_pct = round(100 * (1 - MAE / rw$MAE_RW), 2),
  direction_acc = round(100 * direction_acc, 1)
)]
setorder(metrics, -skill_rmse_pct)

# Cluster bootstrap por data de origem: preserva dependencia cross-sectional no mes.
models <- setdiff(unique(oos$model), "RW")
loss <- dcast(oos[, .(loss = mean(se)), by = .(origin_date, model)],
              origin_date ~ model, value.var = "loss")
B <- 1000L
boot <- rbindlist(lapply(models, function(m) {
  dif <- loss$RW - loss[[m]]
  dif <- dif[is.finite(dif)]
  if (!length(dif)) return(data.table(model = m, loss_diff = NA_real_, p_boot_improve = NA_real_, ci_low = NA_real_, ci_high = NA_real_))
  draws <- replicate(B, mean(sample(dif, replace = TRUE)))
  data.table(model = m,
             loss_diff = mean(dif),
             p_boot_improve = mean(draws <= 0),
             ci_low = quantile(draws, 0.025),
             ci_high = quantile(draws, 0.975))
}))
metrics <- merge(metrics, boot, by = "model", all.x = TRUE)
metrics[model == "RW", `:=`(loss_diff = NA_real_, p_boot_improve = NA_real_, ci_low = NA_real_, ci_high = NA_real_)]
setorder(metrics, -skill_rmse_pct)

by_ticker <- oos[, .(RMSE = sqrt(mean(se)), MAE = mean(abs_err)), by = .(ticker, model)]
rw_t <- by_ticker[model == "RW", .(ticker, RMSE_RW = RMSE, MAE_RW = MAE)]
by_ticker <- merge(by_ticker, rw_t, by = "ticker")
by_ticker[, `:=`(
  skill_rmse_pct = 100 * (1 - RMSE / RMSE_RW),
  skill_mae_pct = 100 * (1 - MAE / MAE_RW)
)]
setorder(by_ticker, ticker, -skill_rmse_pct)

write_tab(metrics, "forecast_consolidated_panel_metrics.csv")
write_tab(by_ticker, "forecast_consolidated_panel_by_ticker.csv")
write_tab(coef_tab, "forecast_consolidated_panel_coefficients.csv")

p <- ggplot(metrics, aes(reorder(model, skill_rmse_pct), skill_rmse_pct)) +
  geom_col(fill = "#2f6f8f") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  coord_flip() +
  labs(title = "Forecast consolidado: skill de RMSE contra random walk",
       x = NULL, y = "% RMSE abaixo do RW") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT_FIG, "forecast_consolidated_panel_skill.png"), p, width = 8.5, height = 4.8, dpi = 160)

cat("\n== FORECAST CONSOLIDADO (todas as acoes elegiveis, h=1, nivel pos_usd) ==\n")
print(metrics)
cat(sprintf("\nCoeficiente n-1 mediano: %.4f | fator mediano: %.4f\n",
            median(coef_tab$beta_n1_market, na.rm = TRUE), median(coef_tab$beta_factor, na.rm = TRUE)))
cat("\nSalvos: forecast_consolidated_panel_metrics.csv, by_ticker, coefficients e figura.\n")
