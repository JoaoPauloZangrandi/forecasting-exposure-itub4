# Passo 3 da CDA: resumo por ano + a pergunta empírica "FIC investe fora da
# própria gestora?". (A detecção de ciclos/profundidade vem no módulo do grafo.)
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4")
source("R/00_config.R"); source("R/01_utils.R"); source("R/04_consolidate_groups.R")

e   <- fread("data/processed/cda_edges.csv",
             colClasses = list(character = c("cnpj_fundo", "cnpj_cota")))
uni <- fread("data/processed/universe_funds.csv", colClasses = list(character = "cnpj"))
uni[, grupo := apply_group(gestora)]
g_of <- setNames(uni$grupo, uni$cnpj)

e[, grupo_origem  := g_of[cnpj_fundo]]
e[, grupo_destino := g_of[cnpj_cota]]
e[, classe := fifelse(cnpj_cota == "", "destino_vazio",
              fifelse(cnpj_cota %in% uni$cnpj, "destino_no_universo", "destino_externo"))]

# --- resumo por ano (leve, versionável) ---
resumo <- e[, .(arestas = .N,
                dt_confid_aplic = sum(confidencial == TRUE),
                destino_vazio = sum(classe == "destino_vazio"),
                destino_no_universo = sum(classe == "destino_no_universo"),
                destino_externo = sum(classe == "destino_externo")), by = ano][order(ano)]
fwrite(resumo, file.path(OUT_TAB, "cda_edges_summary.csv"))
cat("== Resumo por ano ==\n"); print(resumo)

# --- a pergunta: FIC investe fora da própria gestora? ---
intra <- e[classe == "destino_no_universo" & !is.na(grupo_origem) & !is.na(grupo_destino)]
mesma <- intra[grupo_origem == grupo_destino, .N]
outra <- intra[grupo_origem != grupo_destino, .N]
cat("\n== Cotas com destino no universo (", nrow(intra), "arestas) ==\n")
cat(sprintf("  mesma gestora: %d (%.1f%%)\n", mesma, 100 * mesma / nrow(intra)))
cat(sprintf("  OUTRA gestora: %d (%.1f%%)\n", outra, 100 * outra / nrow(intra)))

# --- exemplo Itaú, último mês ---
lm <- max(e$data)
it <- e[grupo_origem == "Itaú" & data == lm]
cat(sprintf("\n== Itau, competencia %s: %d arestas (FIC Itau -> fundo) ==\n", as.character(lm), nrow(it)))
cat(sprintf("  destino Itau: %d | OUTRA gestora: %d | externo/vazio: %d\n",
            it[classe == "destino_no_universo" & grupo_destino == "Itaú", .N],
            it[classe == "destino_no_universo" & grupo_destino != "Itaú", .N],
            it[classe != "destino_no_universo", .N]))
