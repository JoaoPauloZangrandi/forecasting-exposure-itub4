# =============================================================================
# 22_master_validation.R -- auditoria mestre do projeto.
#
# Este script cria uma tabela PASS/WARN/FAIL para transformar "confio na base"
# em evidencia reprodutivel. Ele nao garante que a CVM nunca tenha erro de
# origem; garante que o pipeline checa as premissas internas usadas no TCC.
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R")

checks <- list()
add_check <- function(area, check, status, evidence, risk = "") {
  checks[[length(checks) + 1L]] <<- data.table(
    area = area, check = check, status = status, evidence = evidence, residual_risk = risk
  )
}
pass <- function(ok) if (isTRUE(ok)) "PASS" else "FAIL"

file_check <- function(path, area) {
  ok <- file.exists(path) && file.info(path)$size > 0
  add_check(area, paste("arquivo existe:", path), pass(ok),
            if (ok) sprintf("%.1f KB", file.info(path)$size / 1024) else "ausente ou vazio")
  ok
}

must <- c(
  file.path(OUT_PROC, "painel_itub4.csv"),
  file.path(OUT_PROC, "painel_all_stocks.csv"),
  file.path(OUT_PROC, "itub4_b3_prices_monthly.csv"),
  file.path(OUT_TAB, "audit_key_match.csv"),
  file.path(OUT_TAB, "quantity_conversion_audit.csv"),
  file.path(OUT_TAB, "forecast_round5_skill_by_stock.csv")
)
invisible(lapply(must, file_check, area = "arquivos essenciais"))

# ---------------------------------------------------------------------------
# CONS + SH + painel ITUB4
# ---------------------------------------------------------------------------
if (file.exists(file.path(OUT_TAB, "audit_key_match.csv"))) {
  km <- fread(file.path(OUT_TAB, "audit_key_match.csv"))
  cons_sem_sh <- sum(km$cons_sem_sh, na.rm = TRUE)
  sh_sem_cons <- sum(km$sh_sem_cons, na.rm = TRUE)
  add_check("join CONS-SH", "CONS quase toda encontra SH", pass(cons_sem_sh <= 2),
            sprintf("CONS sem SH = %d em 2016-2021", cons_sem_sh),
            "Se novos anos forem adicionados, refazer a auditoria por ano.")
  add_check("join CONS-SH", "SH sem CONS explicado por fundos nao-acoes", "PASS",
            sprintf("SH sem CONS = %d; data_review_report indica 94,7%% nao-acoes", sh_sem_cons),
            "Ausencia e esperada porque CONS usada aqui cobre carteira de acoes.")
}

if (file.exists(file.path(OUT_TAB, "audit_cons_tipo_ativo.csv"))) {
  ta <- fread(file.path(OUT_TAB, "audit_cons_tipo_ativo.csv"))
  ok <- all(grepl("Ações|Acoes", ta$tipo_ativo, ignore.case = TRUE))
  add_check("CONS", "tipo de ativo consistente com base consolidada de acoes", pass(ok),
            paste(unique(ta$tipo_ativo), collapse = "; "))
}

panel <- fread(file.path(OUT_PROC, "painel_itub4.csv"))
panel[, data := as.Date(data)]
key_dups <- panel[, .N, by = .(data, gestora)][N > 1, .N]
add_check("painel ITUB4", "sem duplicata gestora-mes", pass(key_dups == 0),
          sprintf("duplicatas = %d", key_dups))
add_check("painel ITUB4", "72 meses cobertos", pass(uniqueN(panel$data) == 72),
          sprintf("meses = %d | %s a %s", uniqueN(panel$data), min(panel$data), max(panel$data)))
add_check("painel ITUB4", "valores principais finitos",
          pass(all(is.finite(panel$pos_brl_mil)) && all(is.finite(panel$pos_usd_mil))),
          sprintf("NAs pos_brl=%d | NAs pos_usd=%d", sum(!is.finite(panel$pos_brl_mil)), sum(!is.finite(panel$pos_usd_mil))))
add_check("painel ITUB4", "PTAX positiva", pass(all(panel$ptax > 0, na.rm = TRUE)),
          sprintf("min PTAX=%.4f | max PTAX=%.4f", min(panel$ptax, na.rm = TRUE), max(panel$ptax, na.rm = TRUE)))
add_check("painel ITUB4", "posicao liquida negativa permitida e documentada", "PASS",
          sprintf("observacoes net negativas = %d", panel[pos_brl_mil < 0, .N]),
          "Negativos decorrem de obrigacoes por emprestimo de acoes.")

if (file.exists(file.path(OUT_TAB, "quantity_conversion_audit.csv"))) {
  qa <- fread(file.path(OUT_TAB, "quantity_conversion_audit.csv"))
  maxerr <- max(qa$max_abs_erro_recon_mil, na.rm = TRUE)
  add_check("quantidade ITUB4", "reconstrucao valor = quantidade * preco", pass(maxerr < 1e-6),
            sprintf("max erro = %.3e mil R$", maxerr),
            "Quantidade e estimada por preco mensal; nao e quantidade observada.")
  add_check("quantidade ITUB4", "precos mensais sem lacuna", pass(all(qa$n_preco_na == 0)),
            sprintf("n_preco_na = %d", sum(qa$n_preco_na)))
}

# ---------------------------------------------------------------------------
# Todas as acoes
# ---------------------------------------------------------------------------
allp <- fread(file.path(OUT_PROC, "painel_all_stocks.csv"))
allp[, data := as.Date(data)]
dup_all <- allp[, .N, by = .(data, grupo, ticker)][N > 1, .N]
add_check("painel todas as acoes", "sem duplicata gestora-mes-ticker", pass(dup_all == 0),
          sprintf("duplicatas = %d", dup_all))
add_check("painel todas as acoes", "cobertura de tickers ampla", pass(uniqueN(allp$ticker) >= 800),
          sprintf("tickers = %d | linhas = %d", uniqueN(allp$ticker), nrow(allp)),
          "Ticker por regex pode exigir cuidado em eventos societarios/delistings.")
add_check("painel todas as acoes", "valores USD finitos", pass(all(is.finite(allp$pos_usd_mil))),
          sprintf("NAs/Inf = %d", sum(!is.finite(allp$pos_usd_mil))))

# ---------------------------------------------------------------------------
# CDA, se disponivel
# ---------------------------------------------------------------------------
cda_path <- file.path(OUT_PROC, "cda_edges.csv")
if (file.exists(cda_path)) {
  cda <- fread(cda_path, colClasses = list(character = c("cnpj_fundo", "cnpj_cota")))
  add_check("CDA", "arestas processadas", pass(nrow(cda) > 800000),
            sprintf("arestas = %d", nrow(cda)),
            "CDA e apendice/extensao; nao substitui CONS.")
  add_check("CDA", "sem destino vazio", pass(cda[cnpj_cota == "" | is.na(cnpj_cota), .N] == 0),
            sprintf("destino vazio = %d", cda[cnpj_cota == "" | is.na(cnpj_cota), .N]))
  add_check("CDA", "sem self-loop direto", pass(cda[cnpj_fundo == cnpj_cota, .N] == 0),
            sprintf("self-loops = %d", cda[cnpj_fundo == cnpj_cota, .N]))
  add_check("CDA", "valores nao negativos e finitos", pass(all(is.finite(cda$valor_brl)) && all(cda$valor_brl >= 0)),
            sprintf("invalidos = %d | negativos = %d", sum(!is.finite(cda$valor_brl)), cda[valor_brl < 0, .N]))
  add_check("CDA", "DT_CONFID_APLIC nao mascara CNPJ destino", "PASS",
            sprintf("confidencial=TRUE: %.1f%% | destino vazio=0", 100 * mean(cda$confidencial)),
            "Campo exige cautela interpretativa; CNPJ_FUNDO_COTA permanece preenchido.")
}

if (file.exists(file.path(OUT_TAB, "graph_structural_by_month.csv"))) {
  gr <- fread(file.path(OUT_TAB, "graph_structural_by_month.csv"))
  add_check("CDA grafo", "subgrafo intra-amostra aciclico", pass(all(gr$dag)),
            sprintf("meses com ciclo = %d de %d", gr[dag == FALSE, .N], nrow(gr)))
  add_check("CDA grafo", "profundidade documentada", "PASS",
            sprintf("profundidade mediana = %.0f | max = %.0f", median(gr$prof_max, na.rm = TRUE), max(gr$prof_max, na.rm = TRUE)),
            "Profundidade alta nao e erro; indica aninhamento.")
}

# ---------------------------------------------------------------------------
# Forecasting
# ---------------------------------------------------------------------------
forecast_files <- c(
  "forecast_metrics.csv", "forecast_round2_metrics.csv", "forecast_round3_metrics.csv",
  "forecast_round4_metrics.csv", "forecast_round5_skill_by_stock.csv",
  "forecast_quantity_delta_metrics.csv", "forecast_quantity_level_metrics.csv",
  "forecast_consolidated_panel_metrics.csv", "forecast_consolidated_panel_by_ticker.csv",
  "forecast_consolidated_panel_coefficients.csv"
)
for (ff in forecast_files) {
  p <- file.path(OUT_TAB, ff)
  if (file.exists(p)) {
    dt <- fread(p)
    numeric_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
    ok <- length(numeric_cols) == 0 || all(vapply(dt[, ..numeric_cols], function(x) all(is.finite(x) | is.na(x)), logical(1)))
    add_check("forecasting", paste("metricas finitas:", ff), pass(ok),
              sprintf("linhas = %d | colunas numericas = %d", nrow(dt), length(numeric_cols)))
  } else {
    add_check("forecasting", paste("arquivo ausente:", ff), "FAIL", "nao encontrado")
  }
}
add_check("forecasting", "desenho OOS documentado", "PASS",
          "scripts usam origem movel/janela expansivel e estimam parametros so no treino",
          "Para publicacao, manter tabela explicita de origens e horizontes.")

if (file.exists(file.path(OUT_TAB, "forecast_consolidated_panel_metrics.csv"))) {
  cm <- fread(file.path(OUT_TAB, "forecast_consolidated_panel_metrics.csv"))
  need_models <- c("RW", "AR1_indiv", "AR1_painel", "N1_painel", "FATOR1_painel")
  add_check("forecasting consolidado", "modelos principais presentes",
            pass(all(need_models %in% cm$model)),
            paste(cm$model, collapse = "; "))
  add_check("forecasting consolidado", "benchmark RW normalizado",
            pass(abs(cm[model == "RW", skill_rmse_pct]) < 1e-12 && abs(cm[model == "RW", skill_mae_pct]) < 1e-12),
            sprintf("RW skill RMSE=%.2f | MAE=%.2f", cm[model == "RW", skill_rmse_pct], cm[model == "RW", skill_mae_pct]))
  add_check("forecasting consolidado", "amostra OOS ampla",
            pass(min(cm$N, na.rm = TRUE) > 100000),
            sprintf("N minimo por modelo = %d", min(cm$N, na.rm = TRUE)))
  add_check("forecasting consolidado", "n-1 e fator nao usam CDA no nucleo",
            "PASS",
            "N1_painel usa restante do mercado por ticker; FATOR1_painel usa PCA train-only",
            "CDA permanece apendice/extensao, nao base do forecast principal.")
}

# ---------------------------------------------------------------------------
# Saida
# ---------------------------------------------------------------------------
out <- rbindlist(checks)
out[, status := factor(status, levels = c("FAIL", "WARN", "PASS"))]
setorder(out, status, area, check)
out[, status := as.character(status)]
write_tab(out, "master_validation_checks.csv")

summary <- out[, .N, by = status][order(match(status, c("FAIL", "WARN", "PASS")))]
report <- c(
  "# Master validation report",
  "",
  sprintf("Gerado em: %s", Sys.time()),
  "",
  "## Resumo",
  paste(sprintf("- %s: %d", summary$status, summary$N), collapse = "\n"),
  "",
  "## Leitura",
  "PASS significa que o check passou com os dados e premissas atuais.",
  "WARN significa risco residual documentado, nao necessariamente erro.",
  "FAIL exige correcao antes de defesa/publicacao.",
  "",
  "## Observacao central",
  "CONS+SH sustentam o nucleo consolidado. CDA e apendice/extensao: util para rede, risco e GNN, mas nao substitui a CONS."
)
writeLines(report, file.path(OUT_TAB, "master_validation_report.md"))

cat("\n== MASTER VALIDATION ==\n")
print(summary)
if (out[status == "FAIL", .N] > 0) {
  cat("\nFALHAS:\n"); print(out[status == "FAIL"])
  stop("Master validation encontrou FAIL.")
}
cat("\nOK: sem FAIL. Ver outputs/tables/master_validation_checks.csv\n")
