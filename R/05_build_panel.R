# =============================================================================
# 05_build_panel.R — painel gestora × mês para ITUB4.
# Alvo primário (decisão do orientador): POSIÇÃO em R$ e US$ e sua variação
# mensal. Peso é descritivo. Posição = NET (direta + cedida + obrigações).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(stringr); library(jsonlite) })

# PTAX (R$/US$) de fim de mês — BCB SGS série 1.
get_ptax <- function() {
  url <- sprintf(
    "https://api.bcb.gov.br/dados/serie/bcdata.sgs.%d/dados?formato=json&dataInicial=%s&dataFinal=%s",
    PTAX_SGS_SERIE, PTAX_INI, PTAX_FIM)
  dt <- as.data.table(jsonlite::fromJSON(url))
  dt[, data := as.Date(data, format = "%d/%m/%Y")]
  dt[, ptax := as.numeric(gsub(",", ".", valor))]
  dt[, `:=`(ano = year(data), mes = month(data))]
  setorder(dt, data)
  dt[, .SD[.N], by = .(ano, mes)][, .(ano, mes, ptax)]   # última cotação do mês
}

build_panel <- function(itub4_fm, sh_monthly, ptax_monthly, exposicao = EXPOSICAO) {
  sh <- copy(sh_monthly)
  sh[, gestora_grp := apply_group(gestora)]
  # Blindagem: gestora em branco/NA vira NA (evita "grupo fantasma" se algum ano
  # tiver GESTORA vazia). Nestes dados (2016-2021) não há nenhuma, então não muda
  # os resultados; é proteção para extensões futuras.
  sh[is.na(gestora) | trimws(gestora) == "", gestora_grp := NA_character_]
  sh[, pl_valido := is.finite(pl_mil) & pl_mil > 0]

  # Posição ITUB4 por fundo-mês, larga por variante.
  fm <- dcast(itub4_fm, data + codigo_fundo + cnpj ~ variante,
              value.var = "valor_mil", fun.aggregate = sum, fill = 0)
  for (v in c("direta", "cedida", "obrigacao"))
    if (!v %in% names(fm)) fm[, (v) := 0]
  fm[, pos := switch(exposicao,
                     direta = direta,
                     long   = direta + cedida,
                     net    = direta + cedida + obrigacao)]

  # Atribui cada fundo a uma gestora (grupo) via SH; o que não casa é auditado.
  fm_g <- merge(fm, sh[, .(data, codigo_fundo, cnpj, gestora_grp)],
                by = c("data", "codigo_fundo", "cnpj"), all.x = TRUE)
  unmatched <- fm_g[is.na(gestora_grp),
                    .(data, codigo_fundo, cnpj, direta, cedida, obrigacao, pos)]
  fm_g <- fm_g[!is.na(gestora_grp)]

  pos_g <- fm_g[, .(
    pos_brl_mil      = sum(pos, na.rm = TRUE),
    valor_direta_mil = sum(direta, na.rm = TRUE),
    valor_cedida_mil = sum(cedida, na.rm = TRUE),
    valor_obrig_mil  = sum(obrigacao, na.rm = TRUE),
    n_fundos_itub4   = uniqueN(paste(codigo_fundo, cnpj))
  ), by = .(data, gestora_grp)]

  pl_g <- sh[pl_valido == TRUE & !is.na(gestora_grp), .(
    pl_mil = sum(pl_mil, na.rm = TRUE),
    n_fundos_gestora = uniqueN(paste(codigo_fundo, cnpj))
  ), by = .(data, gestora_grp)]

  # Universo do painel = (data, gestora) com PL válido. Sem ITUB4 -> posição 0.
  panel <- merge(pl_g, pos_g, by = c("data", "gestora_grp"), all.x = TRUE)
  zero_cols <- c("pos_brl_mil", "valor_direta_mil", "valor_cedida_mil", "valor_obrig_mil")
  for (c0 in zero_cols) panel[is.na(get(c0)), (c0) := 0]
  panel[is.na(n_fundos_itub4), n_fundos_itub4 := 0L]

  panel[, `:=`(ano = year(data), mes = month(data))]
  panel <- merge(panel, ptax_monthly, by = c("ano", "mes"), all.x = TRUE)
  panel[, pos_usd_mil := pos_brl_mil / ptax]
  panel[, peso_itub4 := fifelse(pl_mil > 0, pos_brl_mil / pl_mil, NA_real_)]

  # Variações mensais "gap-safe": só entre meses consecutivos (<= GAP_MAX_DIAS).
  setorder(panel, gestora_grp, data)
  panel[, gap := as.numeric(data - shift(data)), by = gestora_grp]
  panel[, consec := !is.na(gap) & gap <= GAP_MAX_DIAS]
  panel[, delta_pos_brl_mil := fifelse(consec, pos_brl_mil - shift(pos_brl_mil), NA_real_), by = gestora_grp]
  panel[, delta_pos_usd_mil := fifelse(consec, pos_usd_mil - shift(pos_usd_mil), NA_real_), by = gestora_grp]
  panel[, c("gap", "consec") := NULL]

  setnames(panel, "gestora_grp", "gestora")
  setcolorder(panel, c("data", "ano", "mes", "gestora",
                       "pos_brl_mil", "pos_usd_mil", "ptax",
                       "valor_direta_mil", "valor_cedida_mil", "valor_obrig_mil",
                       "n_fundos_itub4", "pl_mil", "n_fundos_gestora", "peso_itub4",
                       "delta_pos_brl_mil", "delta_pos_usd_mil"))
  list(panel = panel[], unmatched = unmatched)
}

# Estacionariedade (ADF): não diferenciar o peso; diferenciar a posição.
run_adf <- function(panel) {
  panel[, .(
    n       = sum(is.finite(pos_usd_mil)),
    p_peso  = adf_pvalue(peso_itub4),
    p_pos   = adf_pvalue(pos_usd_mil),
    p_delta = adf_pvalue(delta_pos_usd_mil)
  ), by = gestora][n >= ADF_MIN_OBS][order(gestora)]
}
