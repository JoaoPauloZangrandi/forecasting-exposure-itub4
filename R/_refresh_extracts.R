# Regenera itub4_fundmonth.csv e pl_fundmonth.csv a partir do cache FRESCO
# (já deduplicado pelo re-run do 99). Rápido — não relê os CSV brutos.
suppressPackageStartupMessages(library(data.table))
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R")
L <- readRDS(CACHE_LOAD)
fm <- dcast(L$cons$itub4_fm, data + codigo_fundo + cnpj ~ variante,
            value.var = "valor_mil", fun.aggregate = sum, fill = 0)
for (v in c("direta","cedida","obrigacao")) if (!v %in% names(fm)) fm[, (v) := 0]
fm[, itub4_net_mil := direta + cedida + obrigacao]
fwrite(fm[, .(data, cnpj, codigo_fundo, direta, cedida, obrigacao, itub4_net_mil)],
       file.path(OUT_PROC, "itub4_fundmonth.csv"))
fwrite(L$sh$sh_monthly[, .(data, cnpj, codigo_fundo, gestora, is_fic, pl_mil)],
       file.path(OUT_PROC, "pl_fundmonth.csv"))
cat("extracts por fundo regenerados (deduplicados)\n")
