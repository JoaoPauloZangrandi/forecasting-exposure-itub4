# =============================================================================
# forecasting_scaffold.R  —  ESQUELETO. **NÃO É EXECUTADO NESTA FASE.**
#
# Os modelos de previsão (e o PCA) só devem rodar após autorização explícita.
# Este arquivo apenas documenta o arcabouço previsto, para discussão.
# Entrada: data/processed/painel_itub4.csv (gestora x mes; alvo = posicao US$).
# =============================================================================

stop("forecasting_scaffold.R e apenas um esqueleto; nao deve ser executado nesta fase.")

# ----------------------------------------------------------------------------
# Alvo (decisao do orientador): variacao mensal da posicao em US$ por gestora
#   y_{i,t} = delta_pos_usd_mil[i, t]
# Avaliacao: erro out-of-sample com origem movel (rolling origin), comparando:
#
# (A) Baselines de series temporais
#     - Naive / random walk (delta = 0)
#     - AR(p) por gestora; VAR entre gestoras (poucas gestoras -> regularizar)
#
# (B) Fatores latentes de demanda (PCA / analise fatorial — Artes & Barroso)
#     - PCA sobre a matriz [meses x gestoras] de delta_pos_usd (so na janela de
#       treino, para nao vazar futuro); regredir cada gestora nos k fatores.
#     - Comparar com analise fatorial (cap. 4) e interpretar cargas.
#
# (C) Grafo de gestoras/fundos (GNN / temporal GNN)
#     - Requer a base CDA-BLC (cotas de fundos) para as arestas fundo->fundo.
#     - Node = gestora (ou fundo); features = posicao, PL, fluxo; aresta =
#       co-participacao / "detem cotas de"; alvo = delta de exposicao.
#     - Referencia: Sanchez-Lengeling et al., Distill 2021 (intro a GNN).
#
# Metricas: RMSE / MAE out-of-sample, Diebold-Mariano entre modelos, e
# avaliacao por gestora e agregada.
# ----------------------------------------------------------------------------
