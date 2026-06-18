# =============================================================================
# 21_cda_graph_figures.R -- figuras de grafo para o apendice CDA.
#
# Objetivo:
#   1) visualizar um subgrafo real fundo->fundo da CDA;
#   2) visualizar uma projecao gestora->gestora das arestas observadas;
#   3) desenhar o mapa do desenho empirico: forecast consolidado como nucleo,
#      CDA como apendice/rede e possivel extensao de graph learning.
#
# Observacao metodologica:
#   O TCC nao "preve o grafo" no estado atual. O alvo e a exposicao consolidada
#   por gestora x acao x mes. O grafo CDA e uma camada auxiliar para entender
#   estruturas fundo-sobre-fundo e, no futuro, criar features/modelos de rede.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(igraph)
  library(ggplot2)
  library(grid)
})

.this <- { a <- commandArgs(FALSE); h <- grep("--file=", a, value = TRUE)
           if (length(h)) normalizePath(sub("--file=", "", h[1])) else NA }
if (!is.na(.this)) setwd(dirname(dirname(.this)))
source("R/00_config.R")
source("R/01_utils.R")
source("R/04_consolidate_groups.R")

edges <- fread("data/processed/cda_edges.csv",
               colClasses = list(character = c("cnpj_fundo", "cnpj_cota")))
pl <- fread("data/processed/pl_fundmonth.csv", colClasses = list(character = "cnpj"))

edges[, data := as.Date(data)]
pl[, data := as.Date(data)]
ref_date <- max(edges$data, na.rm = TRUE)
edm <- edges[data == ref_date & cnpj_fundo != "" & cnpj_cota != ""]

plm <- pl[data == ref_date, .(pl_mil = sum(pl_mil, na.rm = TRUE),
                              gestora = gestora[1]), by = cnpj]
plm[, grupo := apply_group(gestora)]

node_map <- unique(rbindlist(list(
  edm[, .(cnpj = cnpj_fundo)],
  edm[, .(cnpj = cnpj_cota)]
)))
node_map <- merge(node_map, plm[, .(cnpj, grupo)], by = "cnpj", all.x = TRUE)
node_map[, tipo := fifelse(is.na(grupo), "fora CONS+SH", "universo CONS+SH")]
node_map[is.na(grupo), grupo := "Fora do universo"]

ed_agg <- edm[, .(valor_brl = sum(valor_brl, na.rm = TRUE),
                  n_linhas = .N,
                  confidencial = any(confidencial)),
              by = .(from = cnpj_fundo, to = cnpj_cota)]

# ---------------------------------------------------------------------------
# Figura 1: subgrafo real de fundos, filtrado para o nucleo mais conectado.
# ---------------------------------------------------------------------------
g_all <- graph_from_data_frame(ed_agg, directed = TRUE, vertices = node_map)
deg <- degree(g_all, mode = "all")
top_nodes <- names(sort(deg, decreasing = TRUE))[seq_len(min(120, length(deg)))]
g_core <- induced_subgraph(g_all, vids = top_nodes)
g_core <- delete_vertices(g_core, V(g_core)[degree(g_core, mode = "all") == 0])

set.seed(42)
lay <- layout_with_fr(g_core, weights = pmax(log1p(E(g_core)$valor_brl), 0.1),
                      niter = 800)
node_col <- ifelse(V(g_core)$tipo == "universo CONS+SH", "#2b6cb0", "#a0aec0")
node_size <- 3 + 3 * sqrt(degree(g_core, mode = "all")) /
  max(1, sqrt(max(degree(g_core, mode = "all"))))
edge_width <- 0.2 + 1.8 * log1p(E(g_core)$valor_brl) /
  max(log1p(E(g_core)$valor_brl), na.rm = TRUE)
edge_col <- adjustcolor("#4a5568", alpha.f = 0.28)
lab_nodes <- names(sort(degree(g_core, mode = "all"), decreasing = TRUE))[1:min(12, vcount(g_core))]
labels <- rep("", vcount(g_core))
labels[match(lab_nodes, V(g_core)$name)] <- paste0("F", seq_along(lab_nodes))

png(file.path(OUT_FIG, "cda_graph_fund_core.png"), width = 1800, height = 1200, res = 180)
par(mar = c(0, 0, 3, 0), bg = "white")
plot(g_core, layout = lay,
     vertex.color = node_col,
     vertex.frame.color = "white",
     vertex.size = node_size,
     vertex.label = labels,
     vertex.label.cex = 0.65,
     vertex.label.color = "#1a202c",
     edge.arrow.size = 0.18,
     edge.width = edge_width,
     edge.color = edge_col,
     main = sprintf("CDA Bloco 2: subgrafo fundo->fundo mais conectado (%s)", ref_date))
legend("topleft", legend = c("Fundo no universo CONS+SH", "Destino/origem fora do universo"),
       col = c("#2b6cb0", "#a0aec0"), pch = 19, bty = "n", cex = 0.85)
dev.off()

# ---------------------------------------------------------------------------
# Figura 2: projecao gestora->gestora (apenas grupos conhecidos).
# ---------------------------------------------------------------------------
edg <- merge(edm, plm[, .(cnpj, grupo)], by.x = "cnpj_fundo", by.y = "cnpj", all.x = TRUE)
setnames(edg, "grupo", "grupo_origem")
edg <- merge(edg, plm[, .(cnpj, grupo)], by.x = "cnpj_cota", by.y = "cnpj", all.x = TRUE)
setnames(edg, "grupo", "grupo_destino")
proj <- edg[!is.na(grupo_origem) & !is.na(grupo_destino),
            .(valor_brl = sum(valor_brl, na.rm = TRUE), n_arestas = .N),
            by = .(from = grupo_origem, to = grupo_destino)]
proj <- proj[from != to][order(-valor_brl)]
proj_plot <- proj[1:min(.N, 45)]
g_mgr <- graph_from_data_frame(proj_plot, directed = TRUE)

set.seed(7)
lay_mgr <- layout_with_kk(g_mgr, weights = 1 / pmax(log1p(E(g_mgr)$valor_brl), 1e-6),
                          maxiter = 1500)
mgr_deg <- degree(g_mgr, mode = "all")
mgr_size <- 14 + 16 * sqrt(mgr_deg) / max(1, sqrt(max(mgr_deg)))
mgr_edge_width <- 0.5 + 5 * log1p(E(g_mgr)$valor_brl) /
  max(log1p(E(g_mgr)$valor_brl), na.rm = TRUE)

png(file.path(OUT_FIG, "cda_graph_manager_projection.png"), width = 1800, height = 1200, res = 180)
par(mar = c(0, 0, 3, 0), bg = "white")
plot(g_mgr, layout = lay_mgr,
     vertex.color = "#234e52",
     vertex.frame.color = "white",
     vertex.size = mgr_size,
     vertex.label = V(g_mgr)$name,
     vertex.label.cex = 0.78,
     vertex.label.color = "#1a202c",
     vertex.label.dist = 0.65,
     edge.arrow.size = 0.28,
     edge.curved = 0.18,
     edge.width = mgr_edge_width,
     edge.color = adjustcolor("#c05621", alpha.f = 0.35),
     main = sprintf("Projecao gestora->gestora: cotas de fundos entre casas (%s)", ref_date))
dev.off()

# ---------------------------------------------------------------------------
# Figura 3: desenho empirico do projeto.
# ---------------------------------------------------------------------------
nodes <- data.table(
  id = c("cons", "sh", "panel", "target", "features", "models", "cda", "appendix", "gnn"),
  x = c(0, 0, 2.2, 4.4, 2.2, 4.4, 0, 2.2, 4.4),
  y = c(3.2, 1.9, 2.55, 2.55, 1.1, 1.1, -0.35, -0.35, -0.35),
  label = c("CONS\ncarteira consolidada",
            "SH\ngestora e PL",
            "Painel consolidado\ngestora x acao x mes",
            "Alvo\nE[g,i,t+h]",
            "Features\nhistorico proprio + n-1",
            "Baselines\nRW, AR, PCA, painel",
            "CDA Bloco 2\ncotas de fundos",
            "Apendice de rede\naninhamento, ciclos, duplicacao",
            "Extensao possivel\nfeatures de rede / GNN")
)
arrows <- data.table(
  x = c(0.55, 0.55, 2.75, 2.75, 0.55, 2.75),
  y = c(3.2, 1.9, 2.55, 1.1, -0.35, -0.35),
  xend = c(1.65, 1.65, 3.85, 3.85, 1.65, 3.85),
  yend = c(2.75, 2.35, 2.55, 1.1, -0.35, -0.35)
)

p_design <- ggplot() +
  geom_segment(data = arrows, aes(x = x, y = y, xend = xend, yend = yend),
               arrow = arrow(length = unit(0.18, "cm")), linewidth = 0.6,
               color = "#4a5568") +
  geom_label(data = nodes, aes(x = x, y = y, label = label),
             label.size = 0.25, fill = "white", color = "#1a202c",
             size = 3.5, lineheight = 0.95, label.padding = unit(0.22, "lines")) +
  annotate("text", x = 2.2, y = 3.85, label = "Nucleo do TCC: forecast consolidado",
           fontface = "bold", size = 4.2, color = "#1a202c") +
  annotate("text", x = 2.2, y = -1.0, label = "Apendice CDA: rede fundo-sobre-fundo e extensao para modelos de grafo",
           fontface = "bold", size = 3.7, color = "#744210") +
  coord_cartesian(xlim = c(-0.8, 5.2), ylim = c(-1.3, 4.1), expand = FALSE) +
  theme_void() +
  theme(plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
ggsave(file.path(OUT_FIG, "research_design_graph.png"), p_design,
       width = 11, height = 6.6, dpi = 180, bg = "white")

notes <- data.table(
  ref_date = ref_date,
  fund_graph_nodes_total = vcount(g_all),
  fund_graph_edges_total = ecount(g_all),
  fund_core_nodes = vcount(g_core),
  fund_core_edges = ecount(g_core),
  manager_projection_nodes = vcount(g_mgr),
  manager_projection_edges = ecount(g_mgr),
  manager_projection_edges_plotted = ecount(g_mgr)
)
write_tab(notes, "cda_graph_visual_notes.csv")

cat("Figuras salvas:\n")
cat(" - outputs/figures/cda_graph_fund_core.png\n")
cat(" - outputs/figures/cda_graph_manager_projection.png\n")
cat(" - outputs/figures/research_design_graph.png\n")
cat("Tabela salva: outputs/tables/cda_graph_visual_notes.csv\n")
