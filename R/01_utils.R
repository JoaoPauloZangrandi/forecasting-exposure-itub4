# =============================================================================
# 01_utils.R — parsers e helpers
# Vários parsers reaproveitados do script anterior (tcc_forecasting_..._pipeline.R),
# que já faziam o parse CORRETO dos números (sem apagar o ponto decimal).
# =============================================================================

log_msg <- function(...) cat(sprintf(...), "\n")

# Desacentua e mantém ASCII (para casar palavras-chave/nomes com robustez).
ascii_text <- function(x) {
  y <- as.character(x)
  z <- iconv(y, from = "", to = "ASCII//TRANSLIT", sub = "")
  z[is.na(z)] <- y[is.na(z)]
  z
}
squish_ascii  <- function(x) stringr::str_squish(ascii_text(x))
deaccent_upper <- function(x) toupper(squish_ascii(x))

# CNPJ só com dígitos.
normalize_cnpj <- function(x) gsub("\\D", "", as.character(x))

# Dinheiro em formato BRASILEIRO: "R$ 49.749,57" -> 49749.57
parse_brl_money <- function(x) {
  if (is.numeric(x) || is.integer(x)) return(as.numeric(x))
  y <- ascii_text(x)
  y <- gsub("R\\$", "", y)
  y <- gsub("\\s+", "", y)
  y <- gsub("\\.", "", y)          # remove separador de milhar
  y <- gsub(",", ".", y)           # vírgula decimal -> ponto
  y <- gsub("[^0-9eE+.-]", "", y)
  suppressWarnings(as.numeric(y))
}

# Número decimal já em formato AMERICANO (CONS). Só remove ponto quando há
# TAMBÉM vírgula (caso brasileiro intruso). Preserva notação científica.
parse_decimal_number <- function(x) {
  if (is.numeric(x) || is.integer(x)) return(as.numeric(x))
  y <- ascii_text(x)
  y <- gsub("\\s+", "", y)
  has_comma <- grepl(",", y)
  has_dot   <- grepl("\\.", y)
  y[has_comma & has_dot] <- gsub("\\.", "", y[has_comma & has_dot])
  y[has_comma] <- gsub(",", ".", y[has_comma])
  y <- gsub("[^0-9eE+.-]", "", y)
  suppressWarnings(as.numeric(y))
}

# Ticker terminal de um nome de ativo: "... - ITUB4" -> "ITUB4".
# Pega 4 letras + 1-2 dígitos no fim da string (após desacentuar/upper).
extract_terminal_ticker <- function(x) {
  stringr::str_trim(stringr::str_extract(deaccent_upper(x), "[A-Z]{4}[0-9]{1,2}\\s*$"))
}

# Classifica a variante de uma linha de ITUB4 pela descrição (robusto a anos):
#   "Obrigações ... recebidos em empréstimo" -> "obrigacao" (valor negativo)
#   "... cedidos em empréstimo"              -> "cedida"
#   caso contrário                            -> "direta"
classify_variant <- function(nome_ativo) {
  up <- deaccent_upper(nome_ativo)
  data.table::fcase(
    grepl("OBRIGAC", up), "obrigacao",
    grepl("CEDID",   up), "cedida",
    default = "direta"
  )
}

# z-score seguro (NA se desvio não positivo).
z_score_safe <- function(x) {
  s <- sd(x, na.rm = TRUE); m <- mean(x, na.rm = TRUE)
  if (is.finite(s) && s > 0) (x - m) / s else rep(NA_real_, length(x))
}

# p-valor do ADF (NA se série curta/constante).
adf_pvalue <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 12L || sd(x) == 0) return(NA_real_)
  suppressWarnings(tryCatch(tseries::adf.test(x)$p.value, error = function(e) NA_real_))
}

# Escrita de tabelas/matrizes de auditoria.
write_tab <- function(x, name) data.table::fwrite(x, file.path(OUT_TAB, name))
write_matrix <- function(x, name, row_name = "gestora") {
  data.table::fwrite(data.table::as.data.table(x, keep.rownames = row_name),
                     file.path(OUT_TAB, name))
}
