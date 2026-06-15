# =============================================================================
# 11_fund_graph.R — grafo fundo-sobre-fundo a partir da CDA Bloco 2.
#   (1) ESTRUTURA por mês: detecção de ciclos e profundidade de aninhamento.
#   (2) LOOK-THROUGH de-duplicado de ITUB4 por gestora: remove a dupla contagem
#       INTERNA (FIC + master da mesma gestora) usando a fração de propriedade.
#
# De-dup (orientador): a soma de consolidados entre fundos da MESMA gestora
# conta a mesma ITUB4 duas vezes. Se A detém fração phi de B (= valor_{A->B}/PL_B),
# a ITUB4 de A inclui phi*L_B, que também está em L_B. Logo:
#   dedup_g = sum_{i in g} L_i  -  sum_{A->B, ambos em g} phi_{A->B} * L_B
# (= soma das posições DIRETAS; cada ação contada uma vez). Cross-gestora e
# externos NÃO entram (não há dupla contagem dentro de g).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(igraph); library(ggplot2) })
.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R"); source("R/01_utils.R"); source("R/04_consolidate_groups.R")

# ---------------------------- dados ----------------------------
edges <- fread("data/processed/cda_edges.csv",
               colClasses = list(character = c("cnpj_fundo", "cnpj_cota")))
itub  <- fread("data/processed/itub4_fundmonth.csv", colClasses = list(character = "cnpj"))
pl    <- fread("data/processed/pl_fundmonth.csv",     colClasses = list(character = "cnpj"))

itub[,  `:=`(ano = year(data), mes = month(data))]
pl[,    `:=`(ano = year(data), mes = month(data))]
edges[, `:=`(ano = year(data), mes = month(data))]

# por CNPJ-mês (somando classes/cotas que dividem CNPJ)
L   <- itub[, .(L_mil = sum(itub4_net_mil, na.rm = TRUE)), by = .(ano, mes, cnpj)]
PLc <- pl[,   .(pl_mil = sum(pl_mil, na.rm = TRUE), gestora = gestora[1]), by = .(ano, mes, cnpj)]
PLc[, grupo := apply_group(gestora)]

# grupo de origem/destino das arestas (só conhecido p/ fundos do universo)
gk <- PLc[, .(ano, mes, cnpj, grupo)]
edges <- merge(edges, gk, by.x = c("ano","mes","cnpj_fundo"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
setnames(edges, "grupo", "grupo_origem")
edges <- merge(edges, gk, by.x = c("ano","mes","cnpj_cota"),  by.y = c("ano","mes","cnpj"), all.x = TRUE)
setnames(edges, "grupo", "grupo_destino")

# ============================================================================
# (1) ESTRUTURA: ciclos e profundidade por mês (subgrafo intra-universo)
# ============================================================================
intra  <- edges[!is.na(grupo_origem) & !is.na(grupo_destino) & cnpj_fundo != cnpj_cota]
months <- unique(intra[, .(ano, mes)])[order(ano, mes)]

longest_path_dag <- function(g) {
  if (!is_dag(g) || ecount(g) == 0) return(NA_integer_)
  ord  <- as.integer(topo_sort(g, mode = "out"))
  dist <- integer(gorder(g))
  for (v in ord) {
    sucs <- as.integer(neighbors(g, v, mode = "out"))
    if (length(sucs)) dist[sucs] <- pmax(dist[sucs], dist[v] + 1L)
  }
  max(dist)
}

struct <- rbindlist(lapply(seq_len(nrow(months)), function(i) {
  ed <- unique(intra[ano == months$ano[i] & mes == months$mes[i], .(cnpj_fundo, cnpj_cota)])
  g  <- graph_from_data_frame(ed, directed = TRUE)
  data.table(ano = months$ano[i], mes = months$mes[i],
             n_nos = gorder(g), n_arestas = ecount(g),
             dag = is_dag(g), prof_max = longest_path_dag(g))
}))
write_tab(struct, "graph_structural_by_month.csv")

cat("== ESTRUTURA (subgrafo intra-amostra, 72 meses) ==\n")
cat("meses com CICLO (nao-DAG):", struct[dag == FALSE, .N], "de", nrow(struct), "\n")
cat("profundidade de aninhamento (max de cadeia, em arestas): mediana",
    median(struct$prof_max, na.rm = TRUE), "| max", max(struct$prof_max, na.rm = TRUE), "\n")
cat("nos/arestas tipicos (ultimo mes):",
    struct[.N, n_nos], "/", struct[.N, n_arestas], "\n")

# ============================================================================
# (2) LOOK-THROUGH DE-DUPLICADO de ITUB4 por gestora
# ============================================================================
Lg    <- merge(L, PLc[, .(ano, mes, cnpj, grupo)], by = c("ano","mes","cnpj"))
gross <- Lg[, .(gross_mil = sum(L_mil, na.rm = TRUE)), by = .(ano, mes, grupo)]

# arestas internas (mesma gestora) com L e PL do destino
se <- edges[grupo_origem == grupo_destino & !is.na(grupo_origem)]
se <- merge(se, L[,   .(ano, mes, cnpj, L_tgt  = L_mil)],  by.x = c("ano","mes","cnpj_cota"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
se <- merge(se, PLc[, .(ano, mes, cnpj, PL_tgt = pl_mil)], by.x = c("ano","mes","cnpj_cota"), by.y = c("ano","mes","cnpj"), all.x = TRUE)
se[, phi := valor_brl / (PL_tgt * 1000)]            # fração de propriedade
se[!is.finite(phi) | PL_tgt <= 0, phi := 0]
se[phi > 1, phi := 1]                                # não se possui >100%
se[is.na(L_tgt), L_tgt := 0]
se[, dup_mil := phi * L_tgt]
dupg <- se[, .(dup_mil = sum(dup_mil, na.rm = TRUE)), by = .(ano, mes, grupo = grupo_origem)]

dd <- merge(gross, dupg, by = c("ano","mes","grupo"), all.x = TRUE)
dd[is.na(dup_mil), dup_mil := 0]
dd[, dedup_mil := gross_mil - dup_mil]
dd[, dup_pct := fifelse(gross_mil != 0, 100 * dup_mil / gross_mil, NA_real_)]
write_tab(dd, "itub4_dedup_by_gestora_month.csv")

# resumo por gestora
resumo <- dd[, .(gross_med_mil = mean(gross_mil), dedup_med_mil = mean(dedup_mil),
                 dup_pct_med = mean(dup_pct, na.rm = TRUE)), by = grupo][order(-gross_med_mil)]
write_tab(resumo, "itub4_dedup_summary.csv")

cat("\n== LOOK-THROUGH DE-DUPLICADO (ITUB4 net) ==\n")
tot_g <- dd[, sum(gross_mil)]; tot_d <- dd[, sum(dedup_mil)]
cat(sprintf("Agregado: bruto %.0f mil -> de-dup %.0f mil  (dupla contagem interna = %.1f%%)\n",
            tot_g, tot_d, 100 * (tot_g - tot_d) / tot_g))
cat("\nTop 8 gestoras (posicao media ITUB4, R$ mi):\n")
print(resumo[1:8, .(grupo,
                    bruto_mi = round(gross_med_mil / 1e3, 1),
                    dedup_mi = round(dedup_med_mil / 1e3, 1),
                    dup_pct = round(dup_pct_med, 1))])

# figura: bruto vs de-dup (Itaú no tempo)
it <- dd[grupo == "Itaú"][order(ano, mes)][, t := as.Date(sprintf("%d-%02d-01", ano, mes))]
if (nrow(it)) {
  p <- ggplot(melt(it[, .(t, bruto = gross_mil/1e3, `de-dup` = dedup_mil/1e3)], id.vars = "t"),
              aes(t, value, color = variable)) +
    geom_line(linewidth = 0.8) +
    labs(title = "Itau: ITUB4 bruto vs de-duplicado (remove dupla contagem interna FIC->master)",
         x = NULL, y = "R$ milhoes", color = NULL) +
    theme_minimal(base_size = 10) + theme(legend.position = "bottom")
  ggsave(file.path(OUT_FIG, "itub4_dedup_itau.png"), p, width = 10, height = 5, dpi = 150)
}
cat("\nSalvos: graph_structural_by_month.csv, itub4_dedup_by_gestora_month.csv,",
    "itub4_dedup_summary.csv, figura itub4_dedup_itau.png\n")
