# =============================================================================
# 17_forecast_round5.R — o forecast de NÍVEL generaliza para todas as ações?
# Rodada 3 mostrou que o nível da posição em ITUB4 reverte à média (AR bate RW
# ~10%). Aqui repetimos para TODAS as ações com histórico suficiente e olhamos a
# DISTRIBUIÇÃO da skill por ação (ITUB4 era especial ou é geral?).
# Alvo: nível pos_usd por gestora x ticker; benchmark RW; OOS origem móvel, h=1.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")
MIN_TRAIN <- 36L; MIN_MONTHS <- 24L; MIN_GEST <- 5L

panel <- fread(file.path(OUT_PROC, "painel_all_stocks.csv"))
if (!"pos_usd_mil" %in% names(panel)) stop("painel_all_stocks.csv sem pos_usd_mil")
alldates <- sort(unique(panel$data))

# tickers elegíveis: >= MIN_GEST gestoras com >= MIN_MONTHS meses detendo a ação
cnt  <- panel[pos_usd_mil > 0, .(m = .N), by = .(ticker, grupo)]
elig <- cnt[m >= MIN_MONTHS]
tks  <- elig[, .(ng = .N), by = ticker][ng >= MIN_GEST, ticker]
log_msg("Acoes avaliaveis: %d (de %d no painel)", length(tks), uniqueN(panel$ticker))

ar_h <- function(x, h = 1L) {
  fit <- tryCatch(ar(x, order.max = 3, aic = TRUE, method = "yule-walker"), error = function(e) NULL)
  if (is.null(fit)) mean(x) else as.numeric(predict(fit, n.ahead = h)$pred)[h]
}

eval_ticker <- function(tk) {
  gs <- elig[ticker == tk, grupo]
  sub <- panel[ticker == tk & grupo %in% gs, .(data, grupo, pos_usd_mil)]
  W <- dcast(sub, data ~ grupo, value.var = "pos_usd_mil")
  W <- merge(data.table(data = alldates), W, by = "data", all.x = TRUE)
  M <- as.matrix(W[, -1]); M[is.na(M)] <- 0
  Tn <- nrow(M); se_rw <- se_ar <- 0; n <- 0L
  for (t in MIN_TRAIN:(Tn - 1)) {
    act <- M[t + 1, ]
    f_ar <- vapply(seq_len(ncol(M)), function(j) ar_h(M[1:t, j], 1L), numeric(1))
    se_rw <- se_rw + sum((act - M[t, ])^2); se_ar <- se_ar + sum((act - f_ar)^2)
    n <- n + ncol(M)
  }
  deg <- se_rw <= .Machine$double.eps
  data.table(ticker = tk, n_gestoras = length(gs),
             rmse_rw = sqrt(se_rw / n), rmse_ar = sqrt(se_ar / n),
             skill_pct = if (deg) NA_real_ else round(100 * (1 - sqrt(se_ar / se_rw)), 1),
             degenerate_rw = deg)
}

res <- rbindlist(lapply(tks, eval_ticker))
setorder(res, -skill_pct)
write_tab(res, "forecast_round5_skill_by_stock.csv")

res_eval <- res[degenerate_rw == FALSE & is.finite(skill_pct)]
cat("\n== RODADA 5: forecast de NIVEL, todas as acoes (skill AR vs RW, h=1) ==\n")
cat(sprintf("acoes avaliadas: %d (%d degeneradas excluidas da estatistica) | skill mediana: %.1f%% | %% acoes com skill>0: %.0f%%\n",
            nrow(res), res[degenerate_rw == TRUE, .N], median(res_eval$skill_pct), 100 * mean(res_eval$skill_pct > 0)))
cat(sprintf("ITUB4: %.1f%% | quartis da skill: %s\n",
            res[ticker == "ITUB4", skill_pct],
            paste(round(quantile(res_eval$skill_pct, c(.25,.5,.75), na.rm = TRUE)), collapse = " / ")))
cat("\nTop 10 e bottom 5 por skill (exclui degeneradas):\n"); print(rbind(head(res_eval, 10), tail(res_eval, 5)))

p <- ggplot(res_eval, aes(skill_pct)) +
  geom_histogram(binwidth = 2, fill = "#2f6f8f", color = "white") +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = res[ticker == "ITUB4", skill_pct], color = "#8f3f2f", linewidth = 0.8) +
  labs(title = "Skill do forecast de nivel (AR vs RW) por acao - linha vermelha = ITUB4",
       x = "% RMSE abaixo do RW", y = "nº de acoes") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT_FIG, "forecast_round5_skill_hist.png"), p, width = 9, height = 5, dpi = 150)
cat("\nOK - forecast_round5_skill_by_stock.csv e figura salvos.\n")
