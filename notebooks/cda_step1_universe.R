# Passo 1 da CDA: salvar o universo de fundos (CNPJ/gestora/FIC) num arquivo leve
# e liberar o cache pesado (3,4 GB) para abrir espaço em disco.
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4")
L <- readRDS("data/processed/_cache_load.rds")
sh <- L$sh$sh_monthly
uni <- sh[, .(gestora = gestora[1], is_fic = any(is_fic),
              codigo_fundo = codigo_fundo[1]), by = cnpj]
fwrite(uni, "data/processed/universe_funds.csv")
cat("fundos no universo (CNPJ unicos):", nrow(uni), "\n")
rm(L); gc()
if (file.exists("data/processed/_cache_load.rds")) {
  file.remove("data/processed/_cache_load.rds")
  cat("cache _cache_load.rds removido (~3,4 GB liberados)\n")
}
