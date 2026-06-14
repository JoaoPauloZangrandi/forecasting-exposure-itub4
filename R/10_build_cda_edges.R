# =============================================================================
# 10_build_cda_edges.R — CDA (Composição NÃO consolidada), Bloco 2: Cotas de
# Fundos. Extrai as arestas fundo->fundo ("detém cotas de") que a CONS apaga.
#
# Baixa os arquivos ANUAIS da pasta HIST, lê o BLC_2 EM STREAMING de dentro do
# zip (o disco é escasso — NÃO extrai para disco), filtra para fundos do nosso
# universo como ORIGEM e apaga o zip após processar.
# Saída: data/processed/cda_edges.csv  (data, cnpj_fundo, cnpj_cota, valor_brl, ...)
# =============================================================================
suppressPackageStartupMessages(library(data.table))
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")

CDA_DIR     <- "C:/Users/joaoz/Downloads/CDA"
CDA_URL     <- "https://dados.cvm.gov.br/dados/FI/DOC/CDA/DADOS/HIST/cda_fi_%d.zip"
DELETE_ZIPS <- TRUE   # disco escasso: apaga o zip depois de ler
dir.create(CDA_DIR, showWarnings = FALSE, recursive = TRUE)
options(timeout = 600)

uni     <- fread("data/processed/universe_funds.csv", colClasses = list(character = "cnpj"))
uni_set <- unique(uni$cnpj)

read_blc2_year <- function(yr) {
  zip <- file.path(CDA_DIR, sprintf("cda_fi_%d.zip", yr))
  if (!file.exists(zip)) {
    log_msg("  baixando CDA %d ...", yr)
    download.file(sprintf(CDA_URL, yr), zip, mode = "wb", quiet = TRUE)
  }
  entry <- sprintf("cda_fi_BLC_2_%d.csv", yr)
  con <- unz(zip, entry, encoding = "latin1"); lines <- readLines(con); close(con)
  dt <- fread(text = lines, sep = ";", header = TRUE,
              select = c("CNPJ_FUNDO", "DT_COMPTC", "VL_MERC_POS_FINAL",
                         "CNPJ_FUNDO_COTA", "DT_CONFID_APLIC"))
  dt[, `:=`(cnpj_fundo   = normalize_cnpj(CNPJ_FUNDO),
            cnpj_cota    = normalize_cnpj(CNPJ_FUNDO_COTA),
            data         = as.Date(as.character(DT_COMPTC)),
            valor_brl    = as.numeric(VL_MERC_POS_FINAL),
            confidencial = !is.na(DT_CONFID_APLIC) & trimws(DT_CONFID_APLIC) != "")]
  n_all <- nrow(dt)
  edges <- dt[cnpj_fundo %in% uni_set,
              .(ano = yr, data, cnpj_fundo, cnpj_cota, valor_brl, confidencial)]
  log_msg("  CDA %d: %d arestas | origem no universo=%d | confidenciais=%d",
          yr, n_all, nrow(edges), edges[confidencial == TRUE | cnpj_cota == "", .N])
  if (DELETE_ZIPS && file.exists(zip)) file.remove(zip)
  rm(dt, lines); gc()
  edges
}

edges <- rbindlist(lapply(YEARS, read_blc2_year))
edges[, dentro_universo := cnpj_cota %in% uni_set]
fwrite(edges, file.path(OUT_PROC, "cda_edges.csv"))

log_msg("---")
log_msg("TOTAL arestas (origem no universo): %d", nrow(edges))
log_msg("  destino TAMBEM no universo: %d (%.1f%%)",
        edges[dentro_universo == TRUE, .N], 100 * mean(edges$dentro_universo))
log_msg("  confidenciais/destino vazio: %d", edges[cnpj_cota == "" | confidencial == TRUE, .N])
log_msg("  fundos-origem distintos: %d | fundos-destino distintos: %d",
        uniqueN(edges$cnpj_fundo), uniqueN(edges$cnpj_cota[edges$cnpj_cota != ""]))
log_msg("Salvo: %s (%.1f MB)", file.path(OUT_PROC, "cda_edges.csv"),
        file.size(file.path(OUT_PROC, "cda_edges.csv")) / 1e6)
