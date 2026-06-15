# =============================================================================
# 12_all_stocks.R — generaliza a análise de ITUB4 para TODAS as ações.
# Produz: painel gestora x mês x ticker (posição net R$/US$), exposição total em
# ações por gestora, look-through de-duplicado da exposição TOTAL (generaliza o
# 37,6% do ITUB4), de-dup por ticker p/ blue chips, e "crowding" (ações detidas
# por muitas gestoras). Não roda forecasting.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(stringr); library(jsonlite); library(ggplot2)
})
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
for (f in c("R/00_config.R","R/01_utils.R","R/04_consolidate_groups.R","R/05_build_panel.R")) source(f)

# Blue chips para de-dup por ticker (exemplos; o painel cobre TODAS as ações).
MARQUEE <- c("ITUB4","ITSA4","PETR4","PETR3","VALE3","BBDC4","BBDC3","ABEV3","B3SA3",
             "BBAS3","WEGE3","BPAC11","RENT3","SUZB3","EQTL3","RADL3","GGBR4","JBSS3","LREN3","ELET3")

# mapa gestora por fundo-mês (do cache regenerado)
L0 <- readRDS(CACHE_LOAD)
shmap <- unique(L0$sh$sh_monthly[, .(data, codigo_fundo, cnpj, gestora)])
rm(L0); gc()

process_year <- function(yr) {
  log_msg("  CONS %d (todas as acoes) ...", yr)
  dt <- fread(file.path(DATA_DIR, sprintf("cons_%d.csv", yr)),
              select = c("CNPJ","Código","Tipo_Ativo","Data_Competência","Nome_Ativo","Valor_Ativo_mil"),
              encoding = "UTF-8", showProgress = FALSE)
  setnames(dt, c("cnpj_raw","codigo_fundo","tipo_ativo","data","nome_ativo","valor_raw"))
  dt[, `:=`(cnpj = normalize_cnpj(cnpj_raw), codigo_fundo = as.character(codigo_fundo),
            data = as.Date(as.character(data)), valor_mil = parse_decimal_number(valor_raw))]
  up <- toupper(dt$nome_ativo)                      # ticker é ASCII; evita iconv
  dt[, ticker := trimws(str_extract(up, "[A-Z]{4}[0-9]{1,2}\\s*$"))]
  n_raw <- nrow(dt)
  dt <- dt[!is.na(ticker) & is.finite(valor_mil)]   # net = soma das variantes (obrig. já negativa)
  cov <- data.table(ano = yr, linhas = n_raw, com_ticker = nrow(dt), n_tickers = uniqueN(dt$ticker))

  fund_eq <- dt[, .(E_mil = sum(valor_mil, na.rm = TRUE)), by = .(data, cnpj)]      # total ações por fundo
  marquee <- dt[ticker %in% MARQUEE, .(L_mil = sum(valor_mil, na.rm = TRUE)), by = .(data, cnpj, ticker)]
  dtg <- merge(dt, shmap, by = c("data","codigo_fundo","cnpj"), all.x = TRUE)
  panel_g <- dtg[!is.na(gestora), .(pos_brl_mil = sum(valor_mil, na.rm = TRUE)),
                 by = .(data, gestora, ticker)]
  rm(dt, dtg, up); gc()
  list(cov = cov, fund_eq = fund_eq, marquee = marquee, panel_g = panel_g)
}

parts   <- lapply(YEARS, process_year)
cov     <- rbindlist(lapply(parts, `[[`, "cov"))
fund_eq <- rbindlist(lapply(parts, `[[`, "fund_eq"))[, .(E_mil = sum(E_mil)), by = .(data, cnpj)]
marquee <- rbindlist(lapply(parts, `[[`, "marquee"))[, .(L_mil = sum(L_mil)), by = .(data, cnpj, ticker)]
panel_g <- rbindlist(lapply(parts, `[[`, "panel_g"))
rm(parts); gc()

# consolida grupos e PTAX
panel_g[, grupo := apply_group(gestora)]
panel <- panel_g[, .(pos_brl_mil = sum(pos_brl_mil, na.rm = TRUE)), by = .(data, grupo, ticker)]
panel[, `:=`(ano = year(data), mes = month(data))]
ptax <- tryCatch(get_ptax(), error = function(e) NULL)
if (!is.null(ptax)) { panel <- merge(panel, ptax, by = c("ano","mes"), all.x = TRUE)
                      panel[, pos_usd_mil := pos_brl_mil / ptax] }
fwrite(panel, file.path(OUT_PROC, "painel_all_stocks.csv"))
write_tab(cov, "all_stocks_coverage.csv")

cat("== COBERTURA ==\n"); print(cov)
cat("\npainel gestora x mes x ticker:", nrow(panel), "linhas |",
    uniqueN(panel$ticker), "tickers |", uniqueN(panel$grupo), "gestoras\n")

# ---------- grupo por fundo-mês (p/ de-dup) ----------
gk <- unique(shmap[, .(data, cnpj, gestora)])
gk[, grupo := apply_group(gestora)]; gk <- unique(gk[, .(data, cnpj, grupo)])
gk[, `:=`(ano = year(data), mes = month(data))]

edges <- fread("data/processed/cda_edges.csv", colClasses = list(character = c("cnpj_fundo","cnpj_cota")))
edges[, `:=`(ano = year(data), mes = month(data))]
edges <- merge(edges, gk[, .(ano,mes,cnpj,go = grupo)], by.x = c("ano","mes","cnpj_fundo"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
edges <- merge(edges, gk[, .(ano,mes,cnpj,gd = grupo)], by.x = c("ano","mes","cnpj_cota"),  by.y = c("ano","mes","cnpj"), all.x = TRUE)
se <- edges[go == gd & !is.na(go)]                  # arestas internas (mesma gestora)

fund_eq[, `:=`(ano = year(data), mes = month(data))]
PL <- gk[, .(ano,mes,cnpj)]                          # PL vem do pl_fundmonth
plf <- fread("data/processed/pl_fundmonth.csv", colClasses = list(character = "cnpj"))
plf[, `:=`(ano = year(data), mes = month(data))]
PLc <- plf[, .(pl_mil = sum(pl_mil, na.rm = TRUE)), by = .(ano,mes,cnpj)]

dedup_total <- function(value_fund, valcol) {
  vf <- copy(value_fund); setnames(vf, valcol, "V")
  fg <- merge(vf[, .(ano,mes,cnpj,V)], gk, by = c("ano","mes","cnpj"))
  gross <- fg[, .(gross_mil = sum(V, na.rm = TRUE)), by = .(ano,mes,grupo)]
  s <- merge(se, vf[, .(ano,mes,cnpj,V_tgt = V)], by.x = c("ano","mes","cnpj_cota"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
  s <- merge(s, PLc[, .(ano,mes,cnpj,PL_tgt = pl_mil)], by.x = c("ano","mes","cnpj_cota"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
  s[, phi := valor_brl / (PL_tgt * 1000)][!is.finite(phi) | PL_tgt <= 0, phi := 0][phi > 1, phi := 1]
  s[is.na(V_tgt), V_tgt := 0][, dup_mil := phi * V_tgt]
  dup <- s[, .(dup_mil = sum(dup_mil, na.rm = TRUE)), by = .(ano,mes,grupo = go)]
  dd <- merge(gross, dup, by = c("ano","mes","grupo"), all.x = TRUE)
  dd[is.na(dup_mil), dup_mil := 0][, dedup_mil := gross_mil - dup_mil]
  dd[, dup_pct := fifelse(gross_mil != 0, 100*dup_mil/gross_mil, NA_real_)]
  dd[]
}

# ---------- de-dup da exposição TOTAL em ações ----------
dd_eq <- dedup_total(fund_eq, "E_mil")
write_tab(dd_eq[, .(ano,mes,grupo,gross_mil,dedup_mil,dup_pct)], "equity_dedup_by_gestora_month.csv")
res_eq <- dd_eq[, .(bruto_mi = round(mean(gross_mil)/1e3,1), dedup_mi = round(mean(dedup_mil)/1e3,1),
                    dup_pct = round(mean(dup_pct, na.rm=TRUE),1)), by = grupo][order(-bruto_mi)]
write_tab(res_eq, "equity_dedup_summary.csv")
tg <- dd_eq[, sum(gross_mil)]; td <- dd_eq[, sum(dedup_mil)]
cat(sprintf("\n== EXPOSICAO TOTAL EM ACOES: de-dup ==\nbruto %.0f mil -> de-dup %.0f mil (dupla contagem %.1f%%)\n",
            tg, td, 100*(tg-td)/tg))
cat("Top 8 gestoras:\n"); print(res_eq[1:8])

# ---------- de-dup por ticker (blue chips) ----------
marquee[, `:=`(ano = year(data), mes = month(data))]
mq <- rbindlist(lapply(MARQUEE, function(tk) {
  vf <- marquee[ticker == tk, .(ano,mes,cnpj,L_mil)]
  if (!nrow(vf)) return(NULL)
  dd <- dedup_total(vf, "L_mil")
  data.table(ticker = tk, bruto_mi = round(sum(dd$gross_mil)/1e3,1),
             dedup_mi = round(sum(dd$dedup_mil)/1e3,1),
             dup_pct = round(100*(sum(dd$gross_mil)-sum(dd$dedup_mil))/sum(dd$gross_mil),1))
}))[order(-bruto_mi)]
write_tab(mq, "marquee_dedup_by_ticker.csv")
cat("\n== DE-DUP POR ACAO (blue chips) ==\n"); print(mq)

# ---------- crowding: acoes detidas por mais gestoras ----------
crowd <- panel[pos_brl_mil > 0, .(n_gestoras = uniqueN(grupo),
                                  pos_media_mensal_mi = round(sum(pos_brl_mil)/uniqueN(paste(ano,mes))/1e3,1)),
               by = ticker][order(-n_gestoras, -pos_media_mensal_mi)]
write_tab(crowd, "stock_crowding.csv")
cat("\n== TOP 15 ACOES MAIS 'CROWDED' (n gestoras) ==\n"); print(crowd[1:15])

# ---------- figura ----------
top <- crowd[1:12, ticker]
agg <- panel[ticker %in% top & pos_brl_mil > 0, .(pos_mi = sum(pos_brl_mil)/uniqueN(paste(panel$ano,panel$mes))/1e3), by = ticker]
p <- ggplot(crowd[1:15], aes(reorder(ticker, n_gestoras), n_gestoras)) +
  geom_col(fill = "#2f6f8f") + coord_flip() +
  labs(title = "Acoes detidas por mais gestoras (crowding)", x = NULL, y = "nº de gestoras") +
  theme_minimal(base_size = 10)
ggsave(file.path(OUT_FIG, "stock_crowding_top15.png"), p, width = 8, height = 5, dpi = 150)

p2 <- ggplot(mq[1:12], aes(reorder(ticker, dup_pct), dup_pct)) +
  geom_col(fill = "#8f3f2f") + coord_flip() +
  labs(title = "Dupla contagem interna por acao (FIC+master, mesma gestora)", x = NULL, y = "% dupla contagem") +
  theme_minimal(base_size = 10)
ggsave(file.path(OUT_FIG, "dedup_pct_by_stock.png"), p2, width = 8, height = 5, dpi = 150)

cat("\nOK — outputs e figuras salvos.\n")
