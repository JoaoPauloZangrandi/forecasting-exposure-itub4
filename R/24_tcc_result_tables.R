# =============================================================================
# 24_tcc_result_tables.R -- tabelas finais para o TCC.
#
# Este script nao muda o pipeline de dados. Ele organiza resultados ja gerados e
# recompõe alguns testes OOS para salvar p-valores/estatisticas que antes ficavam
# apenas no console. A regra de avaliacao permanece fixa:
#   MIN_TRAIN = 36 meses, origem movel, janela expansivel, sem vazamento.
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")

MIN_TRAIN <- 36L
set.seed(1)

panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))

fmt_p <- function(p) fifelse(is.na(p), NA_character_,
                             fifelse(p < 0.001, "<0,001", sprintf("%.3f", p)))
sig_label <- function(p) fifelse(is.na(p), "",
                                 fifelse(p < 0.01, "***",
                                         fifelse(p < 0.05, "**",
                                                 fifelse(p < 0.10, "*", ""))))

make_matrix <- function(col, drop_first = FALSE) {
  w <- dcast(panel, data ~ gestora, value.var = col)
  setorder(w, data)
  M <- as.matrix(w[, -1])
  if (drop_first) M <- M[-1, , drop = FALSE]
  M[, colSums(is.na(M)) == 0, drop = FALSE]
}

ar_forecast <- function(x) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) mean(x) else as.numeric(predict(fit, n.ahead = 1)$pred)
}

pca_forecast <- function(train, k) {
  t <- nrow(train)
  mu <- colMeans(train)
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

eval_delta <- function(col, scale_name) {
  M <- make_matrix(col, drop_first = TRUE)
  Tn <- nrow(M); G <- ncol(M)
  rows <- list()
  for (t in MIN_TRAIN:(Tn - 1)) {
    train <- M[1:t, , drop = FALSE]
    actual <- M[t + 1, ]
    ar <- vapply(seq_len(G), function(j) ar_forecast(train[, j]), numeric(1))
    fc <- list(
      RW = rep(0, G),
      AR = ar,
      AR_encolhido = 0.5 * ar,
      PCA1 = pca_forecast(train, 1),
      PCA2 = pca_forecast(train, 2),
      PCA3 = pca_forecast(train, 3)
    )
    for (m in names(fc)) {
      rows[[length(rows) + 1L]] <- data.table(
        origin = t, gestora = colnames(M), model = m,
        actual = actual, forecast = fc[[m]]
      )
    }
  }
  res <- rbindlist(rows)
  res[, `:=`(se = (actual - forecast)^2, ae = abs(actual - forecast))]
  rw <- res[model == "RW", .(origin, gestora, se_rw = se, ae_rw = ae)]
  met <- res[, .(
    N = .N,
    RMSE = sqrt(mean(se)),
    MAE = mean(ae),
    dir_hit = {
      ok <- actual != 0 & forecast != 0
      if (any(ok)) 100 * mean(sign(forecast[ok]) == sign(actual[ok])) else NA_real_
    },
    dir_n = sum(actual != 0 & forecast != 0),
    dir_success = sum(sign(forecast[actual != 0 & forecast != 0]) == sign(actual[actual != 0 & forecast != 0]))
  ), by = model]
  rmse_rw <- met[model == "RW", RMSE]
  mae_rw <- met[model == "RW", MAE]
  met[, `:=`(
    skill_RMSE = 100 * (1 - RMSE / rmse_rw),
    skill_MAE = 100 * (1 - MAE / mae_rw)
  )]
  met[, p_loss := vapply(model, function(m) {
    if (m == "RW") return(NA_real_)
    d <- merge(res[model == m, .(origin, gestora, se, ae)], rw, by = c("origin", "gestora"))
    tryCatch(t.test(d$se, d$se_rw, paired = TRUE)$p.value, error = function(e) NA_real_)
  }, numeric(1))]
  met[, p_direction := vapply(model, function(m) {
    if (m == "RW") return(NA_real_)
    nn <- met[model == m, dir_n]
    ss <- met[model == m, dir_success]
    if (!is.finite(nn) || nn <= 0) return(NA_real_)
    binom.test(ss, nn, 0.5)$p.value
  }, numeric(1))]
  met[, escala := scale_name]
  met[]
}

delta_usd_tests <- eval_delta("delta_pos_usd_mil", "delta_pos_usd_mil")
delta_qtd_tests <- eval_delta("delta_qtd_itub4", "delta_qtd_itub4")
write_tab(delta_usd_tests, "tcc_delta_usd_tests.csv")
write_tab(delta_qtd_tests, "tcc_delta_quantity_tests.csv")

eval_level <- function(col, target_name, hs = c(1L, 3L, 6L)) {
  M <- make_matrix(col)
  out <- list()
  for (h in hs) {
    Tn <- nrow(M); G <- ncol(M)
    for (t in MIN_TRAIN:(Tn - h)) {
      train <- M[1:t, , drop = FALSE]
      actual <- M[t + h, ]
      mu <- colMeans(train)
      D <- sweep(train, 2, mu)
      Dlag <- D[-t, , drop = FALSE]
      Dnow <- D[-1, , drop = FALSE]
      rho <- sum(Dlag * Dnow, na.rm = TRUE) / sum(Dlag^2, na.rm = TRUE)
      rho <- max(min(rho, 1), -1)
      ar_h <- function(x) {
        fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
        if (is.null(fit)) return(rep(mean(x), h)[h])
        as.numeric(predict(fit, n.ahead = h)$pred)[h]
      }
      fc <- list(
        RW = M[t, ],
        AR_indiv = vapply(seq_len(G), function(j) ar_h(train[, j]), numeric(1)),
        AR1_painel = mu + rho^h * (M[t, ] - mu)
      )
      for (m in names(fc)) {
        out[[length(out) + 1L]] <- data.table(
          h = h, model = m, actual = actual, forecast = fc[[m]]
        )
      }
    }
  }
  res <- rbindlist(out)
  res[, se := (actual - forecast)^2]
  rw <- res[model == "RW", .(obs = .I, h, se_rw = se)]
  res[, obs := seq_len(.N), by = .(h, model)]
  met <- res[, .(N = .N, RMSE = sqrt(mean(se))), by = .(h, model)]
  rw_m <- met[model == "RW", .(h, rmse_rw = RMSE)]
  met <- merge(met, rw_m, by = "h")
  met[, skill_pct := 100 * (1 - RMSE / rmse_rw)]
  met[, p_loss := vapply(seq_len(.N), function(i) {
    m <- met$model[i]; hh <- met$h[i]
    if (m == "RW") return(NA_real_)
    d <- merge(res[h == hh & model == m, .(obs, se)],
               res[h == hh & model == "RW", .(obs, se_rw = se)],
               by = "obs")
    tryCatch(t.test(d$se, d$se_rw, paired = TRUE)$p.value, error = function(e) NA_real_)
  }, numeric(1))]
  met[, target := target_name]
  met[]
}

level_usd_tests <- eval_level("pos_usd_mil", "pos_usd_mil")
level_qtd_tests <- eval_level("qtd_itub4", "qtd_itub4")
write_tab(level_usd_tests, "tcc_level_usd_tests.csv")
write_tab(level_qtd_tests, "tcc_level_quantity_tests.csv")

protocol <- data.table(
  etapa = c("Delta ITUB4 em valor", "Delta ITUB4 em quantidade", "Nivel ITUB4 em valor",
            "Nivel ITUB4 em quantidade", "Todas as acoes", "Forecast consolidado"),
  script = c("R/13 e R/14", "R/20", "R/15", "R/20", "R/17", "R/23"),
  alvo = c("delta_pos_usd_mil", "delta_qtd_itub4", "pos_usd_mil",
           "qtd_itub4", "pos_usd_mil por ticker", "pos_usd_mil por gestora-ticker"),
  unidade = c("gestora-mes", "gestora-mes", "gestora-mes", "gestora-mes",
              "ticker", "gestora-ticker-mes"),
  horizonte = c("1 mes", "1 mes", "1, 3, 6 meses", "1, 3, 6 meses", "1 mes", "1 mes"),
  janela_treino = c(rep("minimo fixo 36 meses; expansivel", 6)),
  significancia = c("t pareado da perda quadratica; binomial de direcao",
                    "t pareado da perda quadratica; binomial de direcao",
                    "t pareado da perda quadratica",
                    "t pareado da perda quadratica",
                    "distribuicao de skill por ticker; degenerados marcados",
                    "bootstrap por data de origem")
)
write_tab(protocol, "tcc_forecast_protocol.csv")

con <- fread(file.path(OUT_TAB, "forecast_consolidated_panel_metrics.csv"))
con_out <- copy(con)
con_out[, `:=`(
  p_valor = fmt_p(p_boot_improve),
  sig = sig_label(p_boot_improve),
  leitura = fifelse(model == "RW", "Benchmark",
                    fifelse(skill_rmse_pct > 0, "Melhora vs RW", "Nao melhora vs RW"))
)]
write_tab(con_out, "tcc_consolidated_significance.csv")

round_summary <- rbindlist(list(
  delta_usd_tests[model %in% c("RW", "AR_encolhido", "AR", "PCA1", "PCA3"),
                  .(bloco = "Delta ITUB4 US$", modelo = model, N, RMSE, MAE, skill_RMSE,
                    p_perda = p_loss, p_direcao = p_direction)],
  delta_qtd_tests[model %in% c("RW", "AR_encolhido", "AR", "PCA1", "PCA3"),
                  .(bloco = "Delta ITUB4 quantidade", modelo = model, N, RMSE, MAE, skill_RMSE,
                    p_perda = p_loss, p_direcao = p_direction)]
), fill = TRUE)
round_summary[, `:=`(p_perda_fmt = fmt_p(p_perda), p_direcao_fmt = fmt_p(p_direcao))]
write_tab(round_summary, "tcc_delta_summary_with_tests.csv")

level_summary <- rbindlist(list(
  level_usd_tests[target == "pos_usd_mil" & model != "RW",
                  .(bloco = "Nivel ITUB4 US$", h, modelo = model, N, RMSE, skill_pct, p_perda = p_loss)],
  level_qtd_tests[target == "qtd_itub4" & model != "RW",
                  .(bloco = "Nivel ITUB4 quantidade", h, modelo = model, N, RMSE, skill_pct, p_perda = p_loss)]
), fill = TRUE)
level_summary[, p_perda_fmt := fmt_p(p_perda)]
write_tab(level_summary, "tcc_level_summary_with_tests.csv")

cat("\nTabelas TCC geradas:\n")
print(c("tcc_forecast_protocol.csv", "tcc_delta_summary_with_tests.csv",
        "tcc_level_summary_with_tests.csv", "tcc_consolidated_significance.csv"))
