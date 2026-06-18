# =============================================================================
# 99_run_all.R — orquestra o pipeline da exposição (SÓ ITUB4).
# Uso: a partir da raiz do projeto:
#   & "C:/Program Files/R/R-4.5.1/bin/Rscript.exe" R/99_run_all.R
# Forçar releitura dos CSV (ignorar cache): FORCE_RELOAD=TRUE
# NÃO roda nenhum modelo de forecast/PCA.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(stringr); library(jsonlite)
  library(ggplot2); library(tseries)
})

# Descobre a raiz do projeto pelo caminho deste script (R/ -> raiz).
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))

for (f in c("R/00_config.R", "R/01_utils.R", "R/02_load_cons.R", "R/03_load_sh.R",
            "R/04_consolidate_groups.R", "R/05_build_panel.R", "R/08_load_prices.R",
            "R/06_diagnostics.R", "R/07_correlation.R")) source(f)

t0 <- Sys.time()

# --- 1. Carga (com cache para acelerar reexecuções) ---
if (file.exists(CACHE_LOAD) && !FORCE_RELOAD) {
  log_msg("Lendo extracts do cache: %s (use FORCE_RELOAD=TRUE para reler os CSV)", CACHE_LOAD)
  L <- readRDS(CACHE_LOAD)
} else {
  cons <- load_cons_all(YEARS)
  sh   <- load_sh_all(YEARS, cons$monthly_dates)
  L <- list(cons = cons, sh = sh)
  saveRDS(L, CACHE_LOAD)
}
cons <- L$cons; sh <- L$sh

# --- 2. Grupos econômicos + PTAX ---
group_map <- build_group_map(sh$sh_monthly$gestora)
ptax <- tryCatch(get_ptax(), error = function(e) {
  warning("Falha ao obter PTAX (", conditionMessage(e), "). Posicao em US$ ficara NA.")
  unique(data.table(ano = year(cons$monthly_dates), mes = month(cons$monthly_dates)))[, ptax := NA_real_]
})
fwrite(ptax, file.path(OUT_TAB, "ptax_mensal.csv"))
prices <- get_itub4_b3_prices(YEARS, TARGET_TICKER)

# --- 3. Painéis nas definições de exposição (direta/long/net) ---
# Na dúvida metodológica, geramos 2+ versões; "direta" = só "ITAUUNIBANCO PN N1 - ITUB4".
expo_summ <- list(); panel_res_net <- NULL
for (expo in EXPOSICOES) {
  pr <- build_panel(cons$itub4_fm, sh$sh_monthly, ptax, prices$monthly, expo)
  p  <- pr$panel
  fwrite(p, file.path(OUT_PROC, sprintf("painel_itub4_%s.csv", expo)))
  write_tab(run_adf(p), sprintf("adf_estacionariedade_%s.csv", expo))
  sfx <- if (expo == "net") "" else paste0("_", expo)
  build_correlations(p, sfx)
  build_quantity_correlations(p, sfx)
  plot_positions(p, sfx)
  plot_quantities(p, sfx)
  expo_summ[[expo]] <- data.table(
    definicao = expo,
    pos_brl_total_mil = sum(p$pos_brl_mil, na.rm = TRUE),
    pos_usd_media_mil = mean(p$pos_usd_mil, na.rm = TRUE),
    qtd_total_mi = sum(p$qtd_itub4, na.rm = TRUE) / 1e6,
    qtd_media_mi = mean(p$qtd_itub4, na.rm = TRUE) / 1e6,
    n_gestora_mes = nrow(p),
    n_pos_negativa = sum(p$pos_brl_mil < 0, na.rm = TRUE),
    n_qtd_negativa = sum(p$qtd_itub4 < 0, na.rm = TRUE),
    peso_mediano = median(p$peso_itub4, na.rm = TRUE),
    peso_max = max(p$peso_itub4, na.rm = TRUE)
  )
  if (expo == "net") panel_res_net <- pr
}
write_tab(rbindlist(expo_summ), "exposure_definitions_comparison.csv")

# Painel primário = net (alias) + ADF/diagnósticos
panel_res <- panel_res_net; panel <- panel_res$panel
fwrite(panel, file.path(OUT_PROC, "painel_itub4.csv"))
write_tab(run_adf(panel), "adf_estacionariedade.csv")
qa <- copy(panel)
qa[, valor_recon_mil := qtd_itub4 * preco_itub4_brl / 1000]
qa[, erro_recon_mil := valor_recon_mil - pos_brl_mil]
write_tab(data.table(
  definicao = EXPOSICAO,
  n_linhas = nrow(qa),
  n_preco_na = sum(is.na(qa$preco_itub4_brl)),
  n_qtd_na = sum(is.na(qa$qtd_itub4)),
  max_abs_erro_recon_mil = max(abs(qa$erro_recon_mil), na.rm = TRUE),
  qtd_total_mi = sum(qa$qtd_itub4, na.rm = TRUE) / 1e6,
  qtd_media_mi = mean(qa$qtd_itub4, na.rm = TRUE) / 1e6,
  qtd_mediana_mi = median(qa$qtd_itub4, na.rm = TRUE) / 1e6
), "quantity_conversion_audit.csv")
run_diagnostics(cons, sh, panel_res, group_map)

log_msg("---")
log_msg("Painel: %d linhas | %d gestoras | %d meses (%s a %s)",
        nrow(panel), uniqueN(panel$gestora), uniqueN(panel$data),
        min(panel$data), max(panel$data))
log_msg("Exposicao=%s | grupos=%s | ITUB4 fund-month=%d",
        EXPOSICAO, CONSOLIDAR_GRUPOS, nrow(cons$itub4_fm))
log_msg("Tempo total: %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins")))
log_msg("Painel salvo em %s", file.path(OUT_PROC, "painel_itub4.csv"))
