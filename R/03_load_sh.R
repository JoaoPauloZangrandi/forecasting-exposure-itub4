# =============================================================================
# 03_load_sh.R — carrega a Série Histórica (SH): gestora + PL por fundo.
# Restringe às datas mensais da CONS e devolve um registro por (data, fundo).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(stringr) })

load_sh_year <- function(yr, monthly_dates) {
  log_msg("  SH %d ...", yr)
  path <- file.path(DATA_DIR, sprintf("SH_%d.csv", yr))
  dt <- fread(
    path,
    select = c("COD_FUNDO", "CNPJ", "NOME_FUNDO", "GESTORA",
               "CLASSIFICACAO_ANBIMA", "DATA", "PATRIMONIO_LIQUIDO_(MIL)"),
    encoding = "UTF-8", showProgress = FALSE
  )
  setnames(dt, c("COD_FUNDO", "CNPJ", "NOME_FUNDO", "GESTORA",
                 "CLASSIFICACAO_ANBIMA", "DATA", "PATRIMONIO_LIQUIDO_(MIL)"),
               c("codigo_fundo", "cnpj_raw", "nome_fundo", "gestora",
                 "classificacao", "data_raw", "pl_raw"))

  pl_class <- paste(class(dt$pl_raw), collapse = "/")   # esperado: "character" (formato BR)
  dt[, `:=`(
    codigo_fundo = as.character(codigo_fundo),
    cnpj = normalize_cnpj(cnpj_raw),
    nome_fundo = str_squish(as.character(nome_fundo)),
    gestora = str_squish(as.character(gestora)),
    classificacao = str_squish(as.character(classificacao)),
    data = as.Date(data_raw, format = "%d/%m/%Y"),
    pl_mil = parse_brl_money(pl_raw)
  )]
  dt[, is_fic := grepl("\\bFIC\\b|EM COTAS", deaccent_upper(nome_fundo))]

  # Diagnóstico por ano na base DIÁRIA completa (antes de filtrar para mensal).
  sh_diag <- dt[, .(
    n_rows_diarias = .N,
    pl_class = pl_class,
    n_gestoras = uniqueN(gestora[!is.na(gestora) & gestora != ""]),
    n_fundos = uniqueN(paste(codigo_fundo, cnpj)),
    n_na_pl = sum(is.na(pl_mil)),
    pct_fic_linhas = mean(is_fic)
  )][, ano := yr][]

  dt <- dt[data %in% monthly_dates]
  list(
    sh_monthly = dt[, .(data, codigo_fundo, cnpj, nome_fundo, gestora,
                        classificacao, pl_mil, is_fic)],
    sh_diag = sh_diag
  )
}

load_sh_all <- function(years, monthly_dates) {
  log_msg("Carregando SH (%d anos)...", length(years))
  parts <- lapply(years, load_sh_year, monthly_dates = monthly_dates)
  sh_monthly <- rbindlist(lapply(parts, `[[`, "sh_monthly"))
  sh_diag    <- rbindlist(lapply(parts, `[[`, "sh_diag"))

  # Checa duplicata (data, fundo) — esperado zero — e garante 1 linha por chave.
  dup_audit <- sh_monthly[, .(N = .N), by = .(data, codigo_fundo, cnpj)][N > 1L]
  sh_monthly <- sh_monthly[, .(
    nome_fundo = first(nome_fundo), gestora = first(gestora),
    classificacao = first(classificacao),
    pl_mil = sum(pl_mil, na.rm = TRUE), is_fic = any(is_fic)
  ), by = .(data, codigo_fundo, cnpj)]

  list(sh_monthly = sh_monthly, sh_diag = sh_diag, dup_audit = dup_audit)
}
