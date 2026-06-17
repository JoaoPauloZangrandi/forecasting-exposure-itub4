# Investiga as linhas duplicadas (cnpj,codigo,data,nome) na CONS 2016 (ITUB4):
# os valores são idênticos (duplicata real -> deduplicar) ou diferentes (lotes)?
# Lê TODAS as 9 colunas, inclusive Anbima e Participação (que o pipeline descarta).
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4"); source("R/01_utils.R")

dt <- fread(file.path("C:/Users/joaoz/Downloads/Consolidado_MF/Consolidado_MF", "cons_2016.csv"),
            encoding = "UTF-8", showProgress = FALSE)
cat("colunas reais:", paste(names(dt), collapse = " | "), "\n\n")
setnames(dt, 1:9, c("cnpj","anbima","cod","nome_fundo","tipo","data","nome_ativo","valor","part"))
dt[, `:=`(cnpj = normalize_cnpj(cnpj), cod = as.character(cod), v = parse_decimal_number(valor))]

it <- dt[grepl("ITUB4", nome_ativo, fixed = TRUE)]
g <- it[, .(n = .N, n_val_distintos = uniqueN(round(v, 4)),
            n_anbima_distintos = uniqueN(anbima), n_nomefundo_distintos = uniqueN(nome_fundo)),
        by = .(cnpj, cod, data, nome_ativo)][n > 1]
cat("ITUB4: grupos (cnpj,cod,data,nome) com >1 linha:", nrow(g), "\n")
cat("  desses, com valores TODOS iguais:", g[n_val_distintos == 1, .N],
    "| com valores diferentes:", g[n_val_distintos > 1, .N], "\n")
cat("  variando Anbima dentro do grupo:", g[n_anbima_distintos > 1, .N], "\n\n")

# mostra 3 grupos de exemplo, com todas as colunas
ex_keys <- g[1:min(3, nrow(g)), .(cnpj, cod, data, nome_ativo)]
ex <- merge(it, ex_keys, by = c("cnpj","cod","data","nome_ativo"))
cat("=== exemplos de linhas duplicadas (todas as colunas) ===\n")
print(ex[order(cnpj, cod, data)][, .(cod, anbima, nome_fundo = substr(nome_fundo,1,25),
                                      nome_ativo = substr(nome_ativo,1,30), v = round(v,2), part)])

# impacto: quanto a soma muda se deduplicarmos linhas EXATAS (mesmo cnpj,cod,data,nome,valor)?
it[, variante := classify_variant(nome_ativo)]
soma_atual <- it[, sum(v, na.rm = TRUE)]
it_dedup <- unique(it, by = c("cnpj","cod","data","nome_ativo","v"))
soma_dedup <- it_dedup[, sum(v, na.rm = TRUE)]
cat(sprintf("\nITUB4 2016 soma atual: %.0f mil | dedup linhas exatas: %.0f mil | diferenca: %.2f%%\n",
            soma_atual, soma_dedup, 100 * (soma_atual - soma_dedup) / soma_atual))
