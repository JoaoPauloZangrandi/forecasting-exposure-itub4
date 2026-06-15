# Passo 4: caracterizar os destinos EXTERNOS (fora da amostra) pela classe do
# fundo, usando o cadastro da CVM (cad_fi). Pergunta: quanto disso é "Ações"
# (relevante p/ ITUB4) vs caixa/RF/multimercado (irrelevante)?
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4")
source("R/01_utils.R")

cad_path <- "C:/Users/joaoz/Downloads/CDA/cad_fi.csv"
if (!file.exists(cad_path)) {
  options(timeout = 300)
  download.file("https://dados.cvm.gov.br/dados/FI/CAD/DADOS/cad_fi.csv",
                cad_path, mode = "wb", quiet = TRUE)
}
cad <- fread(cad_path, sep = ";", encoding = "Latin-1",
             select = c("CNPJ_FUNDO", "CLASSE"))
cad[, cnpj := normalize_cnpj(CNPJ_FUNDO)]
cad <- unique(cad[, .(cnpj, CLASSE)])

e   <- fread("data/processed/cda_edges.csv",
             colClasses = list(character = c("cnpj_fundo", "cnpj_cota")))
uni <- fread("data/processed/universe_funds.csv", colClasses = list(character = "cnpj"))

ext <- e[cnpj_cota != "" & confidencial == FALSE & !(cnpj_cota %in% uni$cnpj)]
ext <- merge(ext, cad, by.x = "cnpj_cota", by.y = "cnpj", all.x = TRUE)
ext[is.na(CLASSE), CLASSE := "(nao achado no cadastro atual)"]

cat("== Destinos EXTERNOS por classe ==\n")
cat("arestas externas:", nrow(ext), "| fundos-destino distintos:", uniqueN(ext$cnpj_cota), "\n\n")
cat("Por VALOR investido (R$ bi) e nº de arestas:\n")
print(ext[, .(valor_bi = round(sum(valor_brl, na.rm = TRUE) / 1e9, 2),
              arestas = .N), by = CLASSE][order(-valor_bi)])

vac <- ext[grepl("[Aa].?[çc][õo]es|ACOES", CLASSE), sum(valor_brl, na.rm = TRUE)]
tot <- ext[, sum(valor_brl, na.rm = TRUE)]
cat(sprintf("\n>>> Destinos externos classificados como ACOES: %.1f%% do valor externo\n",
            100 * vac / tot))
