# =============================================================================
# 04_consolidate_groups.R — consolida entidades do mesmo grupo econômico.
# Casa por REGEX no nome desacentuado/maiúsculo (robusto a variações de grafia
# entre anos), em vez de casar string exata. Primeiro padrão que casar vence.
# Gera tabela de revisão (toda gestora -> grupo) para conferência manual.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(stringr) })

# Ordem importa (primeiro match vence). Aplicado sobre deaccent_upper(gestora).
GROUP_PATTERNS <- c(
  "ITAU"                                                  = "Itaú",
  "BTG PACTUAL|^BTG\\b"                                   = "BTG Pactual",
  "BRADESCO"                                              = "Bradesco",
  "SANTANDER"                                             = "Santander",
  "CAIXA"                                                 = "Caixa",
  "BANCO DO BRASIL|\\bBB\\b|BB DTVM|BB GEST|BB ASSET"     = "BB",
  "CREDIT SUISSE|HEDGING.?GRIFFO"                         = "Credit Suisse",
  "BNP PARIBAS"                                           = "BNP Paribas",
  "SAFRA"                                                 = "Safra",
  "\\bXP\\b|XP INVEST|XP ASSET|XP GEST|XP ADVISORY|XP VISTA|XP CONTROL|XP ALLOCATION" = "XP",
  "\\bJGP\\b"                                             = "JGP"
)

apply_group <- function(gestora) {
  if (!isTRUE(CONSOLIDAR_GRUPOS)) return(as.character(gestora))
  g  <- as.character(gestora)
  gu <- deaccent_upper(g)
  out <- g
  assigned <- rep(FALSE, length(g))
  for (p in names(GROUP_PATTERNS)) {
    hit <- !assigned & !is.na(gu) & grepl(p, gu)
    out[hit] <- GROUP_PATTERNS[[p]]
    assigned <- assigned | hit
  }
  out
}

# Tabela de revisão: para cada gestora original, o grupo atribuído.
build_group_map <- function(gestoras) {
  u <- sort(unique(gestoras[!is.na(gestoras) & gestoras != ""]))
  m <- data.table(gestora_original = u, grupo = apply_group(u))
  m[, consolidada := grupo != gestora_original]
  setorder(m, grupo, gestora_original)
  m[]
}
