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
            "R/04_consolidate_groups.R", "R/05_build_panel.R",
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

# --- 3. Painel ---
panel_res <- build_panel(cons$itub4_fm, sh$sh_monthly, ptax)
panel <- panel_res$panel
fwrite(panel, file.path(OUT_PROC, "painel_itub4.csv"))

# --- 4. Estacionariedade (ADF) ---
adf <- run_adf(panel)
write_tab(adf, "adf_estacionariedade.csv")

# --- 5. Diagnósticos (validação Seção 4) ---
run_diagnostics(cons, sh, panel_res, group_map)

# --- 6. Correlação + figuras (descritivo) ---
build_correlations(panel)
plot_positions(panel)

log_msg("---")
log_msg("Painel: %d linhas | %d gestoras | %d meses (%s a %s)",
        nrow(panel), uniqueN(panel$gestora), uniqueN(panel$data),
        min(panel$data), max(panel$data))
log_msg("Exposicao=%s | grupos=%s | ITUB4 fund-month=%d",
        EXPOSICAO, CONSOLIDAR_GRUPOS, nrow(cons$itub4_fm))
log_msg("Tempo total: %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins")))
log_msg("Painel salvo em %s", file.path(OUT_PROC, "painel_itub4.csv"))
