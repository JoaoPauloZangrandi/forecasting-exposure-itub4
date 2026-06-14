# Passo 2 da CDA: testar leitura do BLC_2 EM STREAMING (sem extrair p/ disco),
# validar colunas, encoding (latin1) e o filtro pelo nosso universo de fundos.
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4")
source("R/01_utils.R")

zip <- "C:/Users/joaoz/Downloads/CDA/cda_fi_2016.zip"
entry <- "cda_fi_BLC_2_2016.csv"

t0 <- Sys.time()
con <- unz(zip, entry, encoding = "latin1")
lines <- readLines(con); close(con)
cat("linhas:", length(lines), "| leitura:",
    round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "s\n")

dt <- fread(text = lines, sep = ";", header = TRUE)
cat("dim:", nrow(dt), "x", ncol(dt), "\n")
cat("colunas:", paste(names(dt), collapse = ", "), "\n")

dt[, `:=`(cnpj_fundo = normalize_cnpj(CNPJ_FUNDO),
          cnpj_cota  = normalize_cnpj(CNPJ_FUNDO_COTA),
          data       = as.Date(as.character(DT_COMPTC)),
          valor      = as.numeric(VL_MERC_POS_FINAL))]

uni <- fread("data/processed/universe_funds.csv", colClasses = list(character = "cnpj"))
edges <- dt[cnpj_fundo %in% uni$cnpj,
            .(data, cnpj_fundo, cnpj_cota, valor, nm_cota = NM_FUNDO_COTA)]

cat("\narestas (todas):", nrow(dt),
    "| com fundo-ORIGEM no nosso universo:", nrow(edges),
    "| cota-DESTINO tambem no universo:", edges[cnpj_cota %in% uni$cnpj, .N], "\n")
cat("datas de competencia no arquivo:", uniqueN(dt$data),
    "->", paste(sort(unique(as.character(dt$data))), collapse = ", "), "\n")
cat("amostra de arestas (origem no universo):\n"); print(head(edges, 4))
