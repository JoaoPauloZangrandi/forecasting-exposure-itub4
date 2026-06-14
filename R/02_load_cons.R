# =============================================================================
# 02_load_cons.R — carrega a base CONS (composição consolidada) por ano.
# Retorna apenas EXTRACTS leves (chaves, ITUB4 por fundo-mês, auditorias);
# o raw (GB) é descartado a cada ano com gc().
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(stringr) })

load_cons_year <- function(yr) {
  log_msg("  CONS %d ...", yr)
  path <- file.path(DATA_DIR, sprintf("cons_%d.csv", yr))
  dt <- fread(
    path,
    select = c("CNPJ", "Código", "Tipo_Ativo", "Data_Competência",
               "Nome_Ativo", "Valor_Ativo_mil"),
    encoding = "UTF-8", showProgress = FALSE
  )
  setnames(dt, c("CNPJ", "Código", "Tipo_Ativo", "Data_Competência",
                 "Nome_Ativo", "Valor_Ativo_mil"),
               c("cnpj_raw", "codigo_fundo", "tipo_ativo", "data",
                 "nome_ativo", "valor_raw"))

  # Diagnóstico-chave de formato: se o fread leu Valor_Ativo_mil como numérico,
  # é PROVA de que a coluna está em ponto decimal e sem vírgula (formato US).
  valor_class <- paste(class(dt$valor_raw), collapse = "/")

  dt[, `:=`(
    cnpj = normalize_cnpj(cnpj_raw),
    codigo_fundo = as.character(codigo_fundo),
    data = as.Date(as.character(data)),
    valor_mil = parse_decimal_number(valor_raw)
  )]

  tipo_audit <- dt[, .(n_rows = .N), by = tipo_ativo][, ano := yr][]

  cons_diag <- data.table(
    ano = yr, n_rows = nrow(dt),
    valor_class = valor_class,
    n_na_valor = sum(is.na(dt$valor_mil)),
    n_na_valor_inesperado = sum(is.na(dt$valor_mil) &
                                  !is.na(dt$valor_raw) &
                                  trimws(as.character(dt$valor_raw)) != ""),
    valor_min = suppressWarnings(min(dt$valor_mil, na.rm = TRUE)),
    valor_max = suppressWarnings(max(dt$valor_mil, na.rm = TRUE)),
    n_fundos  = uniqueN(paste(dt$codigo_fundo, dt$cnpj)),
    n_datas   = uniqueN(dt$data),
    data_min  = min(dt$data, na.rm = TRUE),
    data_max  = max(dt$data, na.rm = TRUE)
  )

  # Linhas cujo "valor" não é numérico mesmo após o parser robusto. Na prática
  # são aspas malformadas no Nome_Ativo (ações de companhia fechada) que jogam
  # texto na coluna de valor. Guardamos para auditoria (espera-se nenhuma ITUB4).
  valor_bad <- dt[is.na(valor_mil) & !is.na(valor_raw) &
                    trimws(as.character(valor_raw)) != "",
                  .(valor_raw = as.character(valor_raw), nome_ativo)][, ano := yr][]

  cons_keys <- unique(dt[, .(data, codigo_fundo, cnpj)])

  # Caminho rápido para o ticker-alvo (pré-filtro fixo); depois confirma pelo
  # ticker terminal (regex genérica, extensível a todas as ações no futuro).
  itub4 <- dt[grepl(TARGET_TICKER, nome_ativo, fixed = TRUE)]
  itub4[, ticker := extract_terminal_ticker(nome_ativo)]
  itub4 <- itub4[ticker == TARGET_TICKER]
  itub4[, variante := classify_variant(nome_ativo)]

  variant_audit <- itub4[, .(
    n_rows = .N,
    n_fundos = uniqueN(paste(codigo_fundo, cnpj)),
    valor_total_mil = sum(valor_mil, na.rm = TRUE),
    data_min = min(data, na.rm = TRUE),
    data_max = max(data, na.rm = TRUE)
  ), by = .(tipo_ativo, nome_ativo, variante)][, ano := yr][]

  itub4_fm <- itub4[is.finite(valor_mil),
                    .(valor_mil = sum(valor_mil, na.rm = TRUE)),
                    by = .(data, codigo_fundo, cnpj, variante)]

  rm(dt, itub4); gc()
  list(cons_keys = cons_keys, itub4_fm = itub4_fm, variant_audit = variant_audit,
       tipo_audit = tipo_audit, cons_diag = cons_diag, valor_bad = valor_bad)
}

load_cons_all <- function(years) {
  log_msg("Carregando CONS (%d anos)...", length(years))
  parts <- lapply(years, load_cons_year)
  cons_keys <- unique(rbindlist(lapply(parts, `[[`, "cons_keys")))
  itub4_fm  <- rbindlist(lapply(parts, `[[`, "itub4_fm"))
  itub4_fm  <- itub4_fm[, .(valor_mil = sum(valor_mil, na.rm = TRUE)),
                        by = .(data, codigo_fundo, cnpj, variante)]
  list(
    cons_keys     = cons_keys,
    itub4_fm      = itub4_fm,
    monthly_dates = sort(unique(cons_keys$data)),
    variant_audit = rbindlist(lapply(parts, `[[`, "variant_audit")),
    tipo_audit    = rbindlist(lapply(parts, `[[`, "tipo_audit")),
    cons_diag     = rbindlist(lapply(parts, `[[`, "cons_diag")),
    valor_bad     = rbindlist(lapply(parts, `[[`, "valor_bad"), fill = TRUE)
  )
}
