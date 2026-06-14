# Auditoria de revisão: consistência interna do painel e tratamento de gestora vazia.
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4")
source("R/01_utils.R")

panel <- fread("data/processed/painel_itub4.csv")
cat("== PAINEL (net) ==\n")
cat("n gestoras:", uniqueN(panel$gestora), "| linhas:", nrow(panel), "\n")
cat("gestora vazia/NA presente?:", any(is.na(panel$gestora) | trimws(panel$gestora) == ""), "\n")
cat("linhas com gestora vazia/NA:", panel[is.na(gestora) | trimws(gestora) == "", .N], "\n")
cat("net = direta+cedida+obrig? max|diff| =",
    panel[, max(abs(pos_brl_mil - (valor_direta_mil + valor_cedida_mil + valor_obrig_mil)))], "\n")
pd <- fread("data/processed/painel_itub4_direta.csv")
cat("direta = valor_direta? max|diff| =", pd[, max(abs(pos_brl_mil - valor_direta_mil))], "\n")

cat("\n== ITUB4 fund-months vs SH (cache) ==\n")
L <- readRDS("data/processed/_cache_load.rds")
sh <- L$sh$sh_monthly
mv <- merge(L$cons$itub4_fm, sh[, .(data, codigo_fundo, cnpj, pl_mil, gestora)],
            by = c("data", "codigo_fundo", "cnpj"), all.x = TRUE)
fm <- unique(L$cons$itub4_fm[, .(data, codigo_fundo, cnpj)])
cat("fund-months com ITUB4:", nrow(fm), "\n")
cat("valor ITUB4 (mil) em fundos com PL NA/<=0:",
    round(mv[is.na(pl_mil) | pl_mil <= 0, sum(valor_mil, na.rm = TRUE)]), "\n")
cat("valor ITUB4 (mil) em fundos com gestora vazia:",
    round(mv[!is.na(gestora) & trimws(gestora) == "", sum(valor_mil, na.rm = TRUE)]), "\n")
cat("valor ITUB4 (mil) em fundos com gestora NA:",
    round(mv[is.na(gestora), sum(valor_mil, na.rm = TRUE)]), "\n")
cat("fundos SH com gestora vazia (nao-NA):", sh[!is.na(gestora) & trimws(gestora) == "", .N], "\n")
cat("fundos SH com gestora NA:", sh[is.na(gestora), .N], "\n")
