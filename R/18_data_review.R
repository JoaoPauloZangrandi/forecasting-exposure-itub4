# =============================================================================
# 18_data_review.R — REVISÃO PROFUNDA das bases (vai além da validação inicial).
# CONS (re-leitura crua): 100% Ações?, linhas de ativo DUPLICADAS, outliers de
#   valor, cobertura de ticker, ITUB4 multi-linha por fundo-mês, sinal das
#   obrigações por ANO.
# SH (cache): classes (codigo) por CNPJ, estabilidade de gestora, PL, duplicatas.
# Join/cobertura: chave CONS x SH, os fundos sem match, o que são os ~25% do SH
#   sem CONS (por classificação ANBIMA).
# CDA: fração de propriedade phi (sanidade de unidades), confidenciais, self-loops.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(stringr) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R"); source("R/04_consolidate_groups.R")
R <- c(); add <- function(...) R[[length(R) + 1L]] <<- sprintf(...)

# ---------------- CONS: re-leitura crua, checagens profundas ----------------
cons_year <- function(yr) {
  dt <- fread(file.path(DATA_DIR, sprintf("cons_%d.csv", yr)),
              select = c("CNPJ","Código","Tipo_Ativo","Data_Competência","Nome_Ativo","Valor_Ativo_mil"),
              encoding = "UTF-8", showProgress = FALSE)
  setnames(dt, c("cnpj","cod","tipo","data","nome","vraw"))
  dt[, `:=`(cnpj = normalize_cnpj(cnpj), cod = as.character(cod), v = parse_decimal_number(vraw))]
  dupk <- dt[, .N, by = .(cnpj, cod, data, nome)][N > 1]
  up <- toupper(dt$nome); tk <- !is.na(str_extract(up, "[A-Z]{4}[0-9]{1,2}\\s*$"))
  it <- dt[grepl("ITUB4", nome, fixed = TRUE)]
  it[, variante := classify_variant(nome)]
  itdup <- it[, .N, by = .(cnpj, cod, data, nome)][N > 1]
  top <- dt[order(-v)][1:3, .(yr = yr, nome = substr(nome, 1, 40), v_mil = round(v))]
  list(
    diag = data.table(ano = yr, linhas = nrow(dt),
                      pct_acoes = round(100 * mean(deaccent_upper(dt$tipo) == "ACOES"), 4),
                      dup_keys = nrow(dupk), dup_extra_linhas = sum(dupk$N - 1L),
                      itub4_dup_keys = nrow(itdup),
                      pct_com_ticker = round(100 * mean(tk), 2),
                      v_neg = sum(dt$v < 0, na.rm = TRUE), v_zero = sum(dt$v == 0, na.rm = TRUE),
                      v_max_mil = round(max(dt$v, na.rm = TRUE)), v_min_mil = round(min(dt$v, na.rm = TRUE))),
    obrig = it[variante == "obrigacao", .(ano = yr, obrig_total_mil = round(sum(v, na.rm = TRUE)),
                                          obrig_n_pos = sum(v > 0, na.rm = TRUE))],
    top = top)
}
log_msg("Relendo CONS para revisao profunda...")
cp <- lapply(YEARS, cons_year)
cons_diag <- rbindlist(lapply(cp, `[[`, "diag"))
obrig <- rbindlist(lapply(cp, `[[`, "obrig"))
write_tab(cons_diag, "review_cons_by_year.csv"); write_tab(rbindlist(lapply(cp, `[[`, "top")), "review_cons_top_values.csv")
add("[CONS] 100%% Acoes todos os anos: %s", all(abs(cons_diag$pct_acoes - 100) < 1e-6))
add("[CONS] linhas de ativo DUPLICADAS (cnpj,cod,data,nome): %d (extra=%d) | ITUB4 dup: %d",
    sum(cons_diag$dup_keys), sum(cons_diag$dup_extra_linhas), sum(cons_diag$itub4_dup_keys))
add("[CONS] cobertura de ticker: %.2f%%-%.2f%% | valores negativos/ano ~%d (obrigacoes)",
    min(cons_diag$pct_com_ticker), max(cons_diag$pct_com_ticker), round(mean(cons_diag$v_neg)))
add("[CONS] obrigacoes NEGATIVAS todo ano: %s (qq positiva? %d)",
    all(obrig$obrig_total_mil < 0), sum(obrig$obrig_n_pos))
add("[CONS] maior valor de uma linha: R$ %.1f bi", max(cons_diag$v_max_mil) / 1e6)

# ---------------- SH (cache): classes, gestora, PL ----------------
L <- readRDS(CACHE_LOAD); sh <- L$sh$sh_monthly; ck <- L$cons$cons_keys
classes <- sh[, .(n_cod = uniqueN(cod <- codigo_fundo)), by = cnpj]
gstab <- sh[, .(n_gest = uniqueN(gestora)), by = .(codigo_fundo, cnpj)]
write_tab(classes[n_cod > 1][order(-n_cod)], "review_sh_classes_por_cnpj.csv")
add("[SH] CNPJ com >1 classe (codigo): %d (max %d) -> PL somado pode contar classes do mesmo fundo",
    classes[n_cod > 1, .N], max(classes$n_cod))
add("[SH] fundos que TROCAM de gestora no tempo: %d", gstab[n_gest > 1, .N])
add("[SH] PL <=0 ou NA (fundo-mes): %d de %d", sh[!(is.finite(pl_mil) & pl_mil > 0), .N], nrow(sh))
add("[SH] duplicatas (data,codigo,cnpj): %d", nrow(L$sh$dup_audit))

# ---------------- Join / cobertura ----------------
ckk <- unique(ck[, .(data, codigo_fundo, cnpj)])[, inc := TRUE]
skk <- unique(sh[, .(data, codigo_fundo, cnpj)])[, ins := TRUE]
km <- merge(ckk, skk, by = c("data","codigo_fundo","cnpj"), all = TRUE)
add("[JOIN] CONS sem SH: %d | SH sem CONS: %d | cobertura SH-em-CONS: %.1f%%",
    km[inc == TRUE & is.na(ins), .N], km[ins == TRUE & is.na(inc), .N],
    100 * km[ins == TRUE, mean(!is.na(inc))])
write_tab(km[inc == TRUE & is.na(ins)], "review_cons_sem_sh.csv")
# o que sao os SH sem CONS? por classificacao
sh_nocons <- merge(sh, ckk, by = c("data","codigo_fundo","cnpj"), all.x = TRUE)[is.na(inc)]
cov_cls <- sh_nocons[, .(n = .N), by = .(eq = grepl("ACOES|ACAO", deaccent_upper(classificacao)))][order(-n)]
add("[JOIN] SH sem CONS: %.1f%% NAO sao de acoes (RF/MM/etc.) -> ausencia esperada",
    100 * cov_cls[eq == FALSE, sum(n)] / cov_cls[, sum(n)])

# ---------------- CDA: phi (unidades), confidenciais, self-loops ----------------
e <- fread("data/processed/cda_edges.csv", colClasses = list(character = c("cnpj_fundo","cnpj_cota")))
add("[CDA] self-loops (fundo detem a propria cota): %d", e[cnpj_fundo == cnpj_cota, .N])
plf <- fread("data/processed/pl_fundmonth.csv", colClasses = list(character = "cnpj"))
plf[, `:=`(ano = year(data), mes = month(data))]
PL <- plf[, .(pl = sum(pl_mil, na.rm = TRUE)), by = .(ano, mes, cnpj)]
e[, `:=`(ano = year(data), mes = month(data))]
es <- merge(e[cnpj_cota != "" & confidencial == FALSE],
            PL, by.x = c("ano","mes","cnpj_cota"), by.y = c("ano","mes","cnpj"))
es[pl > 0, phi := valor_brl / (pl * 1000)]
add("[CDA] phi=valor/PL_destino: mediana %.3f | %% em (0,1]: %.1f%% | %% >1 (capado): %.1f%%",
    median(es$phi, na.rm = TRUE), 100 * mean(es$phi > 0 & es$phi <= 1, na.rm = TRUE),
    100 * mean(es$phi > 1, na.rm = TRUE))
add("[CDA] confidenciais: %.1f%% das arestas (origem no universo)", 100 * mean(e$confidencial | e$cnpj_cota == ""))

R <- unlist(R); writeLines(R, file.path(OUT_TAB, "data_review_report.txt"))
cat("\n================= REVISAO DAS BASES =================\n"); cat(paste(R, collapse = "\n"), "\n")
cat("\nCONS por ano:\n"); print(cons_diag)
cat("\nOK - relatorio em outputs/tables/data_review_report.txt\n")
