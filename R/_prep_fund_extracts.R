# Prep para o grafo: regenera os extracts e salva, por FUNDO-mês, a ITUB4
# (direta/cedida/obrig/net, da CONS look-through) e o PL+gestora (da SH).
# Recria também o cache (3,4 MB). Custa ~7 min (releitura dos 4,2 GB).
suppressPackageStartupMessages({ library(data.table); library(stringr) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
for (f in c("R/00_config.R","R/01_utils.R","R/02_load_cons.R","R/03_load_sh.R")) source(f)

cons <- load_cons_all(YEARS)
sh   <- load_sh_all(YEARS, cons$monthly_dates)
saveRDS(list(cons = cons, sh = sh), CACHE_LOAD)   # restaura o cache

fm <- dcast(cons$itub4_fm, data + codigo_fundo + cnpj ~ variante,
            value.var = "valor_mil", fun.aggregate = sum, fill = 0)
for (v in c("direta","cedida","obrigacao")) if (!v %in% names(fm)) fm[, (v) := 0]
fm[, itub4_net_mil := direta + cedida + obrigacao]
fwrite(fm[, .(data, cnpj, codigo_fundo, direta, cedida, obrigacao, itub4_net_mil)],
       file.path(OUT_PROC, "itub4_fundmonth.csv"))

fwrite(sh$sh_monthly[, .(data, cnpj, codigo_fundo, gestora, is_fic, pl_mil)],
       file.path(OUT_PROC, "pl_fundmonth.csv"))

cat("itub4_fundmonth:", nrow(fm), "linhas | pl_fundmonth:", nrow(sh$sh_monthly), "linhas\n")
