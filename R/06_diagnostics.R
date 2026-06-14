# =============================================================================
# 06_diagnostics.R — valida os fatos da Seção 4 contra os dados reais e
# escreve tabelas de auditoria em outputs/tables/ + um relatório de texto.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(stringr) })

read_header <- function(path) {
  con <- file(path, open = "r", encoding = "UTF-8"); on.exit(close(con))
  h <- readLines(con, n = 1, warn = FALSE)
  gsub("^\\x{FEFF}", "", h, perl = TRUE)
}

run_diagnostics <- function(cons, sh, panel_res, group_map) {
  log_msg("== DIAGNOSTICOS (validacao contra a Secao 4) ==")
  R <- character(0)
  add <- function(...) R[[length(R) + 1L]] <<- sprintf(...)
  flag <- function(ok) if (isTRUE(ok)) "[OK]" else "[!!]"

  # 1) Cabeçalhos / separador / nº de colunas
  files <- c(file.path(DATA_DIR, sprintf("cons_%d.csv", YEARS)),
             file.path(DATA_DIR, sprintf("SH_%d.csv", YEARS)))
  hdr <- data.table(arquivo = basename(files),
                    base = rep(c("CONS", "SH"), each = length(YEARS)),
                    header = vapply(files, read_header, character(1)))
  hdr[, n_cols := str_count(header, ";") + 1L]
  write_tab(hdr, "audit_headers.csv")
  cons_hdr_ok <- uniqueN(hdr[base == "CONS", header]) == 1L
  sh_hdr_ok   <- uniqueN(hdr[base == "SH", header]) == 1L
  add("%s Cabecalhos CONS identicos entre anos (%d cols)  | SH identicos (%d cols)",
      flag(cons_hdr_ok && sh_hdr_ok), hdr[base=="CONS", n_cols[1]], hdr[base=="SH", n_cols[1]])

  # 2) Formato de número da CONS. O formato é decimal americano (ponto). Em
  # alguns anos o fread tipa a coluna como character por causa de ~22 linhas com
  # aspas malformadas no Nome_Ativo (acoes de companhia fechada) que jogam texto
  # na coluna de valor — nenhuma e ITUB4. O parser robusto as descarta (NA).
  write_tab(cons$cons_diag, "audit_cons_number_format.csv")
  if (!is.null(cons$valor_bad)) write_tab(cons$valor_bad, "audit_cons_valor_nao_parseado.csv")
  tot_rows <- sum(cons$cons_diag$n_rows)
  tot_bad  <- sum(cons$cons_diag$n_na_valor_inesperado)
  itub4_bad <- !is.null(cons$valor_bad) && nrow(cons$valor_bad) > 0 &&
               any(grepl("ITUB4", cons$valor_bad$nome_ativo))
  cons_num_ok <- (tot_bad / tot_rows) < 1e-5 && !itub4_bad
  add("%s Valor_Ativo_mil decimal US; %d/%d linhas nao-numericas (aspas malformadas, nao-ITUB4=%s) -> NA",
      flag(cons_num_ok), tot_bad, tot_rows, !itub4_bad)

  # 3) 100% "Ações"
  write_tab(cons$tipo_audit[order(ano, -n_rows)], "audit_cons_tipo_ativo.csv")
  tipo <- cons$tipo_audit[, .(n_rows = sum(n_rows)), by = tipo_ativo]
  pct_acoes <- tipo[deaccent_upper(tipo_ativo) == "ACOES", sum(n_rows)] / tipo[, sum(n_rows)]
  add("%s CONS e 100%% 'Acoes': %.4f%% (tipos distintos=%d)",
      flag(isTRUE(all.equal(pct_acoes, 1))), 100 * pct_acoes, nrow(tipo))

  # 4) Variantes de ITUB4 + sinal das obrigações + magnitudes 2016
  va <- cons$variant_audit[, .(n_rows = sum(n_rows),
                               valor_total_mil = sum(valor_total_mil)),
                           by = .(variante, nome_ativo)][order(variante, -abs(valor_total_mil))]
  write_tab(va, "audit_itub4_variants.csv")
  va16 <- cons$variant_audit[ano == 2016, .(valor_total_mil = sum(valor_total_mil)), by = variante]
  obrig_total <- cons$variant_audit[variante == "obrigacao", sum(valor_total_mil)]
  obrig_neg <- is.finite(obrig_total) && obrig_total < 0
  add("%s ITUB4: %d variantes; obrigacoes com sinal negativo (total mil=%.0f)",
      flag(obrig_neg), uniqueN(cons$variant_audit$variante), obrig_total)
  for (v in c("direta", "cedida", "obrigacao")) {
    val <- va16[variante == v, valor_total_mil]
    if (length(val)) add("      2016 %-9s = R$ %.1f bi", v, sum(val) / 1e6)
  }

  # 5) SH por ano (gestoras, %FIC, NA de PL) + duplicatas fundo-dia
  write_tab(sh$sh_diag, "audit_sh_by_year.csv")
  write_tab(sh$dup_audit, "audit_sh_duplicates.csv")
  add("%s SH sem duplicata (data,fundo): %d duplicatas | gestoras 2016=%d, %%FIC linhas 2016=%.1f%%",
      flag(nrow(sh$dup_audit) == 0), nrow(sh$dup_audit),
      sh$sh_diag[ano == 2016, n_gestoras], 100 * sh$sh_diag[ano == 2016, pct_fic_linhas])

  # 6) Alinhamento de datas CONS x SH
  sh_dates <- sort(unique(sh$sh_monthly$data))
  date_align <- data.table(data = cons$monthly_dates,
                           existe_no_sh = cons$monthly_dates %in% sh_dates)
  date_align[, ano := year(data)]
  write_tab(date_align, "audit_cons_dates_in_sh.csv")
  datas_ok <- all(date_align$existe_no_sh)
  add("%s Datas de competencia da CONS presentes no SH: %d/%d",
      flag(datas_ok), sum(date_align$existe_no_sh), nrow(date_align))

  # 7) Match de chave CONS x SH + overlap de CNPJ
  ck <- unique(cons$cons_keys[, .(data, codigo_fundo, cnpj)])[, in_cons := TRUE]
  sk <- unique(sh$sh_monthly[, .(data, codigo_fundo, cnpj)])[, in_sh := TRUE]
  km <- merge(ck, sk, by = c("data", "codigo_fundo", "cnpj"), all = TRUE)
  key_summary <- km[, .(cons_keys = sum(in_cons == TRUE, na.rm = TRUE),
                        sh_keys = sum(in_sh == TRUE, na.rm = TRUE),
                        cons_sem_sh = sum(in_cons == TRUE & is.na(in_sh)),
                        sh_sem_cons = sum(in_sh == TRUE & is.na(in_cons))),
                    by = .(ano = year(data))][order(ano)]
  write_tab(key_summary, "audit_key_match.csv")
  pct_cnpj <- mean(unique(cons$cons_keys$cnpj) %in% unique(sh$sh_monthly$cnpj))
  add("      Chave fundo-mes: CONS sem SH=%d | SH sem CONS=%d | CNPJ da CONS no SH=%.2f%%",
      sum(key_summary$cons_sem_sh), sum(key_summary$sh_sem_cons), 100 * pct_cnpj)

  # 8) Cobertura: dos fundos-mês do SH, quantos têm carteira na CONS
  cov <- merge(sk, ck, by = c("data", "codigo_fundo", "cnpj"), all.x = TRUE)
  cov_sum <- cov[, .(pct_sh_com_cons = mean(!is.na(in_cons))), by = .(data)][order(data)]
  write_tab(cov_sum, "audit_coverage_sh_in_cons.csv")
  add("      Cobertura media (fundos-mes do SH com carteira na CONS): %.1f%%",
      100 * mean(cov_sum$pct_sh_com_cons))

  # 9) ITUB4 sem match no SH (não atribuível a gestora)
  write_tab(panel_res$unmatched, "audit_itub4_unmatched_sh.csv")
  add("      Fundos-mes com ITUB4 sem match no SH (perda de atribuicao): %d",
      nrow(panel_res$unmatched))

  # 10) Duplicação FIC: fundos-mês em que um FIC detém ITUB4 direto
  itub4_funds <- unique(cons$itub4_fm[, .(data, codigo_fundo, cnpj)])
  itub4_fic <- merge(itub4_funds, sh$sh_monthly[, .(data, codigo_fundo, cnpj, is_fic)],
                     by = c("data", "codigo_fundo", "cnpj"), all.x = TRUE)
  fic_dup <- itub4_fic[, .(fundos_itub4 = .N,
                           fundos_itub4_fic = sum(is_fic == TRUE, na.rm = TRUE),
                           pct_fic = mean(is_fic == TRUE, na.rm = TRUE)),
                       by = .(ano = year(data))][order(ano)]
  write_tab(fic_dup, "audit_fic_duplication.csv")
  add("      FICs com ITUB4 direto (possivel dupla contagem direta+indireta): %.1f%% dos fundos-ITUB4",
      100 * mean(fic_dup$pct_fic, na.rm = TRUE))

  # 11) Mapa de grupos
  write_tab(group_map, "audit_gestora_group_map.csv")
  add("      Gestoras: %d originais -> %d grupos (%d consolidadas)",
      nrow(group_map), uniqueN(group_map$grupo), sum(group_map$consolidada))

  R <- unlist(R)
  writeLines(R, file.path(OUT_TAB, "diagnostics_report.txt"), useBytes = TRUE)
  cat(paste(R, collapse = "\n"), "\n")
  invisible(R)
}
