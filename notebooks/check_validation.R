# Investigação pós-execução: (1) tokens não parseáveis na CONS; (2) sanidade do painel.
suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/joaoz/forecasting-exposure-itub4")
source("R/00_config.R"); source("R/01_utils.R")

cat("===== (1) SANIDADE DO PAINEL =====\n")
panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
cat("linhas:", nrow(panel), "| gestoras:", uniqueN(panel$gestora), "\n")
cat("peso_itub4 quantis (0/50/90/99/100%):\n"); print(round(quantile(panel$peso_itub4, c(0,.5,.9,.99,1), na.rm=TRUE), 5))
cat("n peso>1 (impossivel):", sum(panel$peso_itub4 > 1, na.rm=TRUE), "\n")
cat("pos_brl_mil quantis:\n"); print(round(quantile(panel$pos_brl_mil, c(0,.5,.9,1), na.rm=TRUE)))
cat("\nTop 10 gestoras por posicao media em US$ (mil):\n")
print(panel[, .(mean_pos_usd_mil = round(mean(pos_usd_mil, na.rm=TRUE))), by=gestora][order(-mean_pos_usd_mil)][1:10])
cat("\nItau (3 primeiras linhas):\n")
print(head(panel[gestora=="Itaú", .(data, pos_brl_mil, pos_usd_mil, valor_direta_mil, valor_cedida_mil, valor_obrig_mil, peso_itub4)], 3))

cat("\n===== (2) TOKENS NAO PARSEAVEIS EM Valor_Ativo_mil =====\n")
bad <- rbindlist(lapply(YEARS, function(yr){
  p <- file.path(DATA_DIR, sprintf("cons_%d.csv", yr))
  dt <- fread(p, select="Valor_Ativo_mil", colClasses=list(character="Valor_Ativo_mil"),
              encoding="UTF-8", showProgress=FALSE)
  setnames(dt, "valor_raw")
  dt2 <- fread(p, select="Nome_Ativo", encoding="UTF-8", showProgress=FALSE)
  dt[, nome_ativo := dt2[[1]]]
  dt[, v := parse_decimal_number(valor_raw)]
  b <- dt[is.na(v) & !is.na(valor_raw) & trimws(valor_raw) != ""]
  if (nrow(b)) b[, ano := yr][, .(ano, valor_raw, nome_ativo)] else NULL
}), fill=TRUE)
cat("total de linhas nao parseaveis:", nrow(bad), "\n")
cat("tokens distintos (contagem):\n"); print(bad[, .N, by=valor_raw][order(-N)])
cat("alguma e ITUB4?", any(grepl("ITUB4", bad$nome_ativo)), "\n")
cat("amostra de nomes de ativo afetados:\n"); print(head(unique(bad$nome_ativo), 10))
fwrite(bad, file.path(OUT_TAB, "audit_cons_valor_nao_parseado.csv"))
cat("\nOK\n")
