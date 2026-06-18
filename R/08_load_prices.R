# =============================================================================
# 08_load_prices.R — preços oficiais B3/COTAHIST para converter valor em
# quantidade estimada de ações. A CONS não traz quantidade; para ITUB4 usamos:
#   qtd_acoes = Valor_Ativo_mil * 1000 / preco_fechamento_B3
# Fonte: COTAHIST anual da B3, mercado à vista (TPMERC=010).
# =============================================================================
suppressPackageStartupMessages(library(data.table))

B3_COTAHIST_URL <- "https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A%d.ZIP"

parse_cotahist_year <- function(yr, ticker = TARGET_TICKER) {
  zip <- file.path(tempdir(), sprintf("COTAHIST_A%d.ZIP", yr))
  if (!file.exists(zip) || FORCE_RELOAD) {
    log_msg("  baixando COTAHIST B3 %d ...", yr)
    download.file(sprintf(B3_COTAHIST_URL, yr), zip, mode = "wb", quiet = TRUE)
  }

  entry <- sprintf("COTAHIST_A%d.TXT", yr)
  con <- unz(zip, entry, encoding = "latin1")
  on.exit(close(con), add = TRUE)
  x <- readLines(con, warn = FALSE)

  # Registro 01 = cotação diária. CODNEG ocupa posições 13:24.
  x <- x[substr(x, 1L, 2L) == "01" & trimws(substr(x, 13L, 24L)) == ticker]
  if (!length(x)) return(data.table())

  dt <- data.table(
    data = as.Date(substr(x, 3L, 10L), format = "%Y%m%d"),
    ticker = trimws(substr(x, 13L, 24L)),
    codbdi = substr(x, 11L, 12L),
    tpmerc = substr(x, 25L, 27L),
    preco_fechamento_brl = as.numeric(substr(x, 109L, 121L)) / 100,
    negocios = as.integer(substr(x, 148L, 152L)),
    quantidade_negociada = as.numeric(substr(x, 153L, 170L)),
    volume_brl = as.numeric(substr(x, 171L, 188L)) / 100
  )

  # Mercado à vista. Se houver múltiplas linhas no mesmo dia, prioriza CODBDI=02
  # (lote padrão) e, em seguida, a linha com maior volume.
  dt <- dt[tpmerc == "010" & is.finite(preco_fechamento_brl) & preco_fechamento_brl > 0]
  dt[, codbdi_padrao := codbdi == "02"]
  setorder(dt, data, -codbdi_padrao, -volume_brl)
  dt[, codbdi_padrao := NULL]
  unique(dt, by = "data")
}

get_itub4_b3_prices <- function(years = YEARS, ticker = TARGET_TICKER) {
  daily_path <- file.path(OUT_PROC, sprintf("%s_b3_prices_daily.csv", tolower(ticker)))
  monthly_path <- file.path(OUT_PROC, sprintf("%s_b3_prices_monthly.csv", tolower(ticker)))

  if (file.exists(daily_path) && file.exists(monthly_path) && !FORCE_RELOAD) {
    daily <- fread(daily_path)
    monthly <- fread(monthly_path)
    daily[, data := as.Date(data)]
    monthly[, data := as.Date(data)]
    return(list(daily = daily, monthly = monthly))
  }

  log_msg("Carregando preços B3/COTAHIST para %s...", ticker)
  daily <- rbindlist(lapply(years, parse_cotahist_year, ticker = ticker), fill = TRUE)
  if (!nrow(daily)) stop("Nenhuma cotação encontrada na COTAHIST para ", ticker)

  daily[, `:=`(ano = year(data), mes = month(data))]
  setorder(daily, data)
  monthly <- daily[, .SD[.N], by = .(ano, mes)]
  setorder(monthly, ano, mes)

  # Auditoria de cobertura: o painel mensal precisa de 12 meses por ano.
  cov <- monthly[, .(n_meses = .N, data_ini = min(data), data_fim = max(data),
                     preco_min = min(preco_fechamento_brl),
                     preco_max = max(preco_fechamento_brl)), by = ano]
  write_tab(cov, sprintf("%s_b3_price_coverage.csv", tolower(ticker)))

  fwrite(daily, daily_path)
  fwrite(monthly, monthly_path)
  log_msg("  preços mensais: %d meses (%s a %s) | salvo em %s",
          nrow(monthly), min(monthly$data), max(monthly$data), monthly_path)

  list(daily = daily, monthly = monthly)
}
