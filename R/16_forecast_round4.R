# =============================================================================
# 16_forecast_round4.R — a REDE acrescenta sinal? (features de grafo, em R)
# Baseline (rodada 3): o nível da posição US$ reverte à média (AR bate RW ~10%).
# Aqui adicionamos um preditor de REDE: a exposição (defasada) das gestoras
# "vizinhas" no grafo fundo-sobre-fundo (ligações cross-gestora via FICs). Se a
# demanda se propaga pela rede, os vizinhos preveem a gestora além do próprio AR.
#
# Modelos (alvo = nível pos_usd, h=1, OOS origem móvel, sem vazamento):
#   RW          : pos_t
#   AR1_painel  : reversão à média (rho comum, desvios da média da gestora)
#   REDE_painel : idem + termo de exposição dos vizinhos (defasada)
# Adjacência gestora->gestora e médias estimadas SÓ no treino.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R"); source("R/04_consolidate_groups.R")
MIN_TRAIN <- 36L

# --- matriz nível pos_usd (gestoras com cobertura completa) ---
panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
w <- dcast(panel, data ~ gestora, value.var = "pos_usd_mil"); setorder(w, data)
M <- as.matrix(w[, -1]); M <- M[, colSums(is.na(M)) == 0, drop = FALSE]
dates <- w$data; ym <- data.table(idx = seq_along(dates), ano = year(dates), mes = month(dates))
G <- ncol(M); Tn <- nrow(M); gestoras <- colnames(M)
log_msg("Matriz nivel: %d meses x %d gestoras", Tn, G)

# --- arestas gestora->gestora (cross-gestora), por mês ---
edges <- fread("data/processed/cda_edges.csv", colClasses = list(character = c("cnpj_fundo","cnpj_cota")))
edges[, `:=`(ano = year(data), mes = month(data))]
plf <- fread("data/processed/pl_fundmonth.csv", colClasses = list(character = "cnpj"))
plf[, `:=`(ano = year(data), mes = month(data), grupo = apply_group(gestora))]
gk <- unique(plf[, .(ano, mes, cnpj, grupo)])
edges <- merge(edges, gk[, .(ano,mes,cnpj,go = grupo)], by.x = c("ano","mes","cnpj_fundo"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
edges <- merge(edges, gk[, .(ano,mes,cnpj,gd = grupo)], by.x = c("ano","mes","cnpj_cota"),  by.y = c("ano","mes","cnpj"), all.x = TRUE)
Eg <- edges[!is.na(go) & !is.na(gd) & go != gd & go %in% gestoras & gd %in% gestoras,
            .(val = sum(valor_brl, na.rm = TRUE)), by = .(ano, mes, go, gd)]

adj_norm <- function(train_ym) {                 # adjacência média row-normalizada (só treino)
  e <- Eg[paste(ano, mes) %in% train_ym[, paste(ano, mes)], .(val = sum(val)), by = .(go, gd)]
  A <- matrix(0, G, G, dimnames = list(gestoras, gestoras))
  if (nrow(e)) A[cbind(match(e$go, gestoras), match(e$gd, gestoras))] <- e$val
  rs <- rowSums(A); rs[rs == 0] <- 1
  A / rs
}

rows <- list()
for (t in MIN_TRAIN:(Tn - 1)) {
  P <- adj_norm(ym[1:t])                          # G x G, vizinhos (treino)
  NBR <- M[1:t, , drop = FALSE] %*% t(P)          # exposição dos vizinhos, por mês
  mu <- colMeans(M[1:t, , drop = FALSE]); nb <- colMeans(NBR)
  # painel demeaned: s = 1..t-1 prevê s+1
  s <- 1:(t - 1)
  df <- data.table(y  = as.vector(sweep(M[s + 1, , drop = FALSE], 2, mu)),
                   x1 = as.vector(sweep(M[s, , drop = FALSE], 2, mu)),
                   x2 = as.vector(sweep(NBR[s, , drop = FALSE], 2, nb)))
  f_ar  <- lm(y ~ x1 - 1, df)
  f_net <- lm(y ~ x1 + x2 - 1, df)
  x1n <- M[t, ] - mu; x2n <- NBR[t, ] - nb
  fc <- list(RW = M[t, ],
             AR1_painel  = mu + coef(f_ar)["x1"] * x1n,
             REDE_painel = mu + coef(f_net)["x1"] * x1n + coef(f_net)["x2"] * x2n)
  actual <- M[t + 1, ]
  for (m in names(fc))
    rows[[length(rows) + 1L]] <- data.table(origin = t, gestora = gestoras, model = m,
                                            actual = actual, forecast = fc[[m]],
                                            gamma = coef(f_net)["x2"])
}
res <- rbindlist(rows); res[, se := (actual - forecast)^2]
met <- res[, .(RMSE = sqrt(mean(se))), by = model]
rmse_rw <- met[model == "RW", RMSE]
met[, skill_pct := round(100 * (1 - RMSE / rmse_rw), 1)]
setorder(met, -skill_pct)
write_tab(met, "forecast_round4_metrics.csv")
cat("\n== RODADA 4: nivel pos_usd, h=1 (skill vs RW) ==\n"); print(met)
cat(sprintf("\nCoef. de rede (gamma) medio: %.4f  (positivo = exposicao dos vizinhos puxa a sua)\n",
            mean(res$gamma, na.rm = TRUE)))
gn <- met[model == "REDE_painel", skill_pct]; ar <- met[model == "AR1_painel", skill_pct]
cat(sprintf("REDE vs AR puro: %.1f%% vs %.1f%% -> rede %s\n", gn, ar,
            ifelse(gn > ar, "ACRESCENTA sinal", "NAO acrescenta")))
