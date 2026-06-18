# Guia tecnico detalhado do projeto

Este documento existe para explicar o projeto com mais granularidade do que o TCC. O TCC deve ser lido como
documento academico principal; este guia serve para entender decisões, bases, scripts, tratamentos,
resultados, limites e caminhos futuros.

## 1. Ideia em linguagem simples

O projeto mede e tenta prever a exposição consolidada das gestoras brasileiras a ações. O rumo correto, pela
orientação mais recente do orientador, e motivar o TCC como um exercício de forecasting de demanda/exposição:
para cada ação e mes, queremos entender quais gestoras aumentaram ou reduziram exposição e se isso pode ser
previsto usando o histórico da própria gestora e o comportamento do restante do mercado.

A resposta empirica e:

- A medida principal deve ser exposição em valor, em R$ e US$, porque e mais didatica e ligada a risco.
- Quantidade estimada de ações fica como robustez para ITUB4, nao como eixo central.
- A CDA Bloco 2 fica como apendice tecnico robusto: ela reconstrói a rede fundo->fundo que a CONS apaga,
  gera figuras de grafos e prepara uma extensao possivel com modelos de rede.
- A primeira feature manual de rede nao melhorou o AR de painel; isso vira baseline para qualquer extensao
  com grafo, nao resultado central do TCC.

## 2. Estrutura atual da pasta `docs`

A pasta `docs` deve ter apenas:

- `tcc.tex`: fonte unica do TCC.
- `tcc.pdf`: PDF unico do TCC.
- `refs.bib`: bibliografia.
- `guia_tecnico_projeto.md`: este guia detalhado.

Arquivos antigos como `tcc_final`, `tcc_todas_acoes` e `tcc_forecasting` eram versões intermediarias e nao
devem permanecer como TCCs separados.

Fora da pasta `docs`, o arquivo `Comprehend.md` e a documentacao longa: teoria, bases, scripts, resultados,
CDA, grafos e extensao com GNN.

## 3. Fundamentação teorica

### 3.1 Koijen e Yogo

Koijen e Yogo desenvolvem uma abordagem de sistema de demanda para precificação de ativos. A ideia relevante
para este projeto e que carteiras institucionais observadas revelam demanda por ativos. Em vez de olhar
apenas para retornos ou fundamentos, o pesquisador observa as posições dos investidores e tenta entender a
estrutura da demanda.

No projeto, as gestoras sao as unidades de demanda/exposição. Valor em reais e dolares e a medida principal
porque comunica escala economica e risco. Quantidade estimada e usada como robustez quando a pergunta for
separar efeito de preço de mudança aproximada de ações carregadas.

### 3.2 Gabaix e Koijen

Gabaix e Koijen argumentam que mercados podem ser inelasticos. Se a demanda agregada por ações nao responde
muito a preço, fluxos e realocações podem ter impacto grande em preços. Isso motiva olhar para grandes
investidores institucionais e para ações onde todos estao posicionados.

No projeto, isso aparece na ideia de que blue chips muito detidas podem concentrar fragilidade.

### 3.3 Greenwood e Thesmar

Greenwood e Thesmar estudam fragilidade de preços associada a propriedade comum e choques correlacionados.
Se muitos investidores parecidos detem o mesmo ativo, e se esses investidores sofrem choques parecidos,
esse ativo pode ficar mais fragil.

No projeto, isso aparece nas ações crowded: VALE3, PETR4, ITUB4, BBDC4 e outras blue chips detidas por
muitas gestoras.

### 3.4 Artes e Barroso

Artes e Barroso entram como referencia metodologica para PCA e analise fatorial. A ideia e resumir padrões
comuns de movimento entre gestoras por fatores latentes.

No projeto, PCA foi testado para prever a variação mensal de exposição, sempre estimado apenas na janela de
treino para evitar vazamento.

### 3.5 GNN

Sanchez-Lengeling et al. entram como referencia introdutoria para redes neurais em grafo. GNNs sao modelos
que aprendem representações de nos usando atributos dos nos e conexões do grafo.

No projeto, GNN e uma extensao metodologica possivel, nao o nucleo atual. Antes de implementar uma GNN
pesada, testamos uma feature simples de vizinhos. Ela nao melhorou a previsão, mas isso deve ser lido como
baseline: uma media manual de vizinhos e fraca; uma GNN poderia aprender pesos e interações mais ricas. O
alvo seguiria sendo exposição consolidada futura, nao a topologia futura do grafo.

## 4. Bases de dados

### 4.1 CONS

CONS e a composição consolidada de carteiras. Ela informa, para cada fundo e data, quais ativos aparecem na
carteira consolidada.

Caracteristicas:

- granularidade: fundo x mes x ativo;
- periodo: 2016 a 2021;
- separador: `;`;
- codificação: UTF-8;
- valores em formato americano, com ponto decimal;
- no recorte usado, `Tipo_Ativo` e 100% ações.

Por ser consolidada, a CONS ja "ve atraves" de cotas de fundos. Se um FIC investe em um master que detem
ITUB4, a CONS tende a mostrar ITUB4 no resultado consolidado. Isso e bom para medir exposição final a ações,
mas ruim para reconstruir quem investiu em quem.

### 4.2 SH

SH e a serie historica dos fundos. Ela traz:

- codigo do fundo;
- CNPJ;
- nome;
- gestora;
- classificação;
- data;
- patrimonio liquido.

O PL vem em formato brasileiro (`R$ 49.749,57`) e precisa de parser diferente do CONS.

SH e essencial porque CONS nao traz gestora nem PL. A junção e feita por `Código` da CONS igual a
`COD_FUNDO` da SH, com mesmo CNPJ e mesma data de competencia.

### 4.3 CDA

CDA e a Composição e Diversificação das Aplicações. A parte usada e o Bloco 2, cotas de fundos. Ela mostra
relações do tipo:

`fundo A detem cotas do fundo B`.

Colunas usadas:

- `CNPJ_FUNDO`: fundo origem;
- `CNPJ_FUNDO_COTA`: fundo investido;
- `DT_COMPTC`: data da carteira;
- `VL_MERC_POS_FINAL`: valor de mercado da posição;
- `DT_CONFID_APLIC`: campo associado a confidencialidade.

A CDA nao substitui a CONS. A CONS mede a exposição final a ações; a CDA mede o caminho fundo->fundo. No
TCC atual, ela deve aparecer no apendice como auditoria de rede, risco estrutural, visualização de grafos e
base para uma possivel extensao com GNN.

### 4.4 B3/COTAHIST

A CONS nao traz quantidade de ações. Para ITUB4, a quantidade e estimada usando o fechamento mensal da B3:

```text
quantidade = Valor_Ativo_mil * 1000 / preco_fechamento_ITUB4
```

Fonte usada: COTAHIST anual da B3, mercado a vista (`TPMERC=010`), ultimo pregao de cada mes. O script baixa
os zips anuais temporariamente, filtra `CODNEG == ITUB4`, seleciona fechamento (`PREULT`) e grava:

- `data/processed/itub4_b3_prices_daily.csv`;
- `data/processed/itub4_b3_prices_monthly.csv`;
- `outputs/tables/itub4_b3_price_coverage.csv`.

Auditoria: os 72 meses entre 2016 e 2021 estao cobertos, sem preço faltante.

## 5. Tratamentos de dados

### 5.1 CNPJ

Todos os CNPJs sao normalizados para conter apenas digitos. Isso evita erro por pontos, barras e hifens.

Função: `normalize_cnpj()` em `R/01_utils.R`.

### 5.2 Numeros da CONS

`Valor_Ativo_mil` usa formato americano. O parser `parse_decimal_number()` preserva ponto decimal e notação
cientifica. Isso foi importante porque uma versão anterior que removia ponto decimal distorcia magnitudes.

### 5.3 Numeros da SH

PL da SH usa formato brasileiro. O parser `parse_brl_money()` remove `R$`, remove ponto de milhar e troca
virgula decimal por ponto.

### 5.4 Duplicatas exatas da CONS

A revisão profunda encontrou linhas exatamente duplicadas na CONS. A regra implementada remove apenas linhas
com mesmo:

- CNPJ;
- codigo do fundo;
- data;
- nome do ativo;
- valor.

Isso preserva casos legitimos em que o mesmo ativo aparece mais de uma vez com valores diferentes.

Impacto empirico: cerca de 0,2% das linhas e perto de 0,01% nos totais. Mesmo sendo pequeno, a correção e
metodologicamente correta.

### 5.5 Variantes de exposição

Para ITUB4, ha tres variantes:

- direta: `ITAUUNIBANCO PN N1 - ITUB4`;
- cedida: ações cedidas em emprestimo;
- obrigação: obrigações por ações recebidas em emprestimo, valor negativo.

As definições de exposição sao:

- `direta = direta`;
- `long = direta + cedida`;
- `net = direta + cedida + obrigação`.

O trabalho usa `net` como definição principal.

### 5.6 Grupos economicos

Gestoras sao consolidadas por grupo econômico usando regex. Exemplo:

- `Itaú Asset Management`, `Itaú DTVM`, `Itaú Unibanco` viram `Itaú`;
- entidades BTG viram `BTG Pactual`;
- entidades Bradesco viram `Bradesco`.

Script: `R/04_consolidate_groups.R`.

### 5.7 PTAX

Posição em US$ e calculada usando PTAX de fim de mes, BCB SGS serie 1. Isso torna valores comparaveis no
tempo.

Script: função `get_ptax()` em `R/05_build_panel.R`.

### 5.8 Quantidade estimada de ITUB4

Para ITUB4, `R/05_build_panel.R` agora calcula:

- `preco_itub4_brl`;
- `qtd_direta`;
- `qtd_cedida`;
- `qtd_obrig`;
- `qtd_itub4`;
- `delta_qtd_itub4`.

A definição de `qtd_itub4` respeita a definição de exposição:

- direta: `qtd_direta`;
- long: `qtd_direta + qtd_cedida`;
- net: `qtd_direta + qtd_cedida + qtd_obrig`.

A tabela `outputs/tables/quantity_conversion_audit.csv` confirma que:

- nao ha preço faltante;
- nao ha quantidade faltante;
- `qtd_itub4 * preco / 1000` reconstrói `pos_brl_mil` com erro numerico de maquina.

### 5.9 Deltas gap-safe

A variação mensal so e calculada quando os meses sao consecutivos. Isso evita delta artificial quando ha
lacuna de dados.

## 6. Pipeline de codigo

### 6.1 Configuração

`R/00_config.R` define:

- anos;
- ticker alvo;
- definição de exposição;
- diretorios;
- caminho dos dados brutos;
- variavel de ambiente `CVM_DATA_DIR`.

### 6.2 Utilitarios

`R/01_utils.R` contem:

- parsers numericos;
- normalização de CNPJ;
- extração de ticker;
- classificação de variante;
- teste ADF;
- escrita padronizada de tabelas.

### 6.3 Carga CONS

`R/02_load_cons.R` le a CONS ano a ano para evitar manter 4,2 GB em memoria. Ele retorna extracts leves:

- chaves fundo-data-CNPJ;
- ITUB4 por fundo-mes-variante;
- auditorias.

### 6.4 Carga SH

`R/03_load_sh.R` le gestora e PL. Restringe aos meses presentes na CONS. Verifica duplicatas por data,
codigo e CNPJ.

### 6.5 Painel ITUB4

`R/05_build_panel.R` monta o painel gestora-mes:

- posição em R$;
- posição em US$;
- quantidade estimada de ações;
- PL;
- peso;
- deltas;
- componentes direta, cedida e obrigação.

### 6.6 Diagnosticos

`R/06_diagnostics.R` e `R/18_data_review.R` fazem auditorias. A revisão profunda relê a CONS e verifica
duplicatas, cobertura de ticker, outliers, classes por CNPJ, estabilidade de gestora, cobertura CONS-SH e
sanidade da CDA.

### 6.7 Todas as ações

`R/12_all_stocks.R` extrai tickers por regex e monta painel para todas as ações. Ele tambem calcula crowding
e usa a CDA para de-duplicação complementar quando as arestas fundo->fundo estao disponiveis.

### 6.8 Forecasting

Scripts:

- `R/13_forecast_itub4.R`: rodada 1, variação mensal ITUB4;
- `R/14_forecast_round2.R`: regularização, shrinkage, MAE e direção;
- `R/15_forecast_round3.R`: nivel da posição e horizontes 1, 3 e 6;
- `R/16_forecast_round4.R`: features de rede via CDA;
- `R/17_forecast_round5.R`: generalização do forecast de nivel para todas as ações;
- `R/19_half_life.R`: meia-vida da reversão a media em valor, quantidade e peso;
- `R/20_forecast_quantity.R`: forecasting usando quantidade estimada de ITUB4;
- `R/22_master_validation.R`: auditoria mestre PASS/WARN/FAIL;
- `R/23_forecast_consolidated_panel.R`: forecast consolidado gestora x ação x mes com AR, n-1 e fator comum.

## 7. Resultados principais

### 7.1 Exposição ITUB4

Painel ITUB4:

- 2.835 observações gestora-mes;
- 42 grupos;
- 72 meses;
- exposição principal net.

Somas de posições mensais:

- direta: R$ 468 bi;
- long: R$ 540 bi;
- net: R$ 496 bi.

Quantidade estimada acumulada no painel:

- direta: 14,77 bi ações;
- long: 17,02 bi ações;
- net: 15,71 bi ações.

### 7.2 Todas as ações

O painel reconhece 836 tickers. As ações detidas pelo maior numero de gestoras sao blue chips. Isso indica
concentração de demanda institucional em ativos liquidos e centrais no indice.

### 7.3 Forecast da variação em quantidade

Resultado: sem previsibilidade robusta.

- AR encolhido melhora apenas 0,6% em RMSE e piora em MAE.
- PCA piora, especialmente com mais fatores.
- Direção fica perto de 50%.

Interpretação: variação mensal da demanda aproximada e muito ruidosa.

### 7.4 Forecast do nivel

Resultado: previsibilidade aparece mais claramente no nivel da posição em US$ do que na quantidade.

- ITUB4: AR individual reduz RMSE em cerca de 10%.
- Em quantidade, AR individual melhora 3,5% em h=1, mas perde para o random walk em h=3 e h=6.
- Isso indica que a reversão em valor nao deve ser vendida como reversão forte de demanda.

### 7.5 Forecast consolidado final

O teste final usa todas as ações elegiveis no painel gestora x ação x mes. A especificação compara random
walk, AR1 individual, AR1 de painel, n-1 (restante do mercado na mesma ação) e fator comum por PCA.

Resultado:

- 235 ações avaliadas depois de excluir 3 tickers degenerados;
- 183.924 previsões OOS por modelo;
- nenhum modelo supera o random walk no agregado;
- coeficiente mediano de n-1: 0,0054;
- coeficiente mediano do fator comum: 0,0009;
- bootstrap por mes nao indica melhora robusta.

Leitura: ITUB4 tem reversão a media no nivel em valor, mas o ganho nao generaliza para o painel amplo como
previsibilidade agregada robusta.

### 7.6 Half-life

O AR(1) no nivel estima velocidade de reversão a alocação-alvo.

Resultado:

- valor em US$: 36 de 37 gestoras revertem, rho mediano perto de 0,77, meia-vida mediana de 2,8 meses;
- quantidade estimada: 33 de 37 gestoras revertem, rho mediano perto de 0,83, meia-vida mediana de 3,8 meses;
- pooled em quantidade: rho perto de 0,891, meia-vida de 6,0 meses.

### 7.6 CDA e de-duplicação

Resultado complementar:

- 835.694 arestas fundo->fundo;
- 72 meses;
- zero destinos vazios;
- `DT_CONFID_APLIC` preenchido em 32,3% das arestas;
- phi mediano perto de 0,007;
- 98,6% dos phi validos em `(0,1]`;
- duplicação intra-gestora de ITUB4: 37,6%;
- duplicação in-universe total rastreavel de ITUB4, incluindo cross-gestora: cerca de 43,0%.

## 8. Como interpretar a CDA corretamente

A CDA deve ser interpretada como apendice tecnico de rede:

- CONS mede exposição final em ações;
- CDA mede o caminho fundo->fundo;
- o Bloco 2 e exatamente cotas de fundos;
- a auditoria mostra valores plausiveis;
- o resultado de dupla contagem e economicamente relevante;
- a rede CDA e uma extensao natural para forecasting via graph network, mas nao muda o alvo principal.

Formula segura:

> A CDA Bloco 2 e a base usada, em apendice, para reconstruir a rede fundo-sobre-fundo apagada pela CONS
> consolidada. Ela permite medir aninhamento, testar circularidade, estimar duplicação, criar figuras de
> grafos e preparar features de rede para uma extensao de forecasting.

Formula a evitar:

> A CDA prova que 32% dos destinos estao mascarados.

Isso esta errado para o arquivo processado, porque `CNPJ_FUNDO_COTA` esta preenchido mesmo quando
`DT_CONFID_APLIC` existe.

## 9. GNN em detalhe

### 9.1 O que seria um GNN aqui

Uma GNN usaria:

- nos: gestoras ou fundos;
- arestas: relações fundo->fundo da CDA, possivelmente agregadas para gestora->gestora;
- features dos nos: posição atual, PL, peso, delta, histórico recente;
- alvo: posição futura ou variação futura.

### 9.2 Possivel desenho em nivel de gestora

Para cada mes:

- matriz de features `X_t`: gestoras x atributos;
- matriz de adjacencia `A_t`: peso das relações entre gestoras;
- alvo `y_{t+1}`: posição futura ou delta futuro.

Um modelo simples:

1. normalizar `A_t`;
2. aplicar camada GCN: `H = ReLU(A_t X_t W_1)`;
3. prever: `y_hat = H W_2`;
4. avaliar out-of-sample com origem movel.

### 9.3 O que ja foi testado

Antes de implementar GNN, o projeto testou uma feature de rede simples: exposição dos vizinhos. Essa feature
nao melhorou o AR de painel. Resultado:

- AR1 painel: skill 3,3%;
- rede painel: skill 3,1%;
- coeficiente de rede praticamente zero.

Isso nao elimina GNN. O teste apenas mostra que uma feature manual de vizinhos e fraca. Uma GNN ou outro
modelo de grafo pode aprender pesos, direções e não linearidades que a media simples nao captura.

### 9.4 Quando uma GNN faria sentido

Faz sentido como extensao porque:

- o orientador explicitou a ideia de previsão por graphs network;
- a CDA ja fornece as arestas fundo->fundo;
- o painel gestora x ação x mes ja fornece os alvos de exposição consolidada;
- a comparação contra random walk, AR, painel, n-1 e fatores ja existe.

### 9.5 Riscos de GNN

- painel curto: 72 meses;
- poucos nos se agregarmos por gestora;
- grafo CDA tem destinos externos;
- risco de overfitting;
- instalação de PyTorch/PyTorch Geometric pode consumir tempo;
- explicabilidade menor do que AR e half-life.

## 10. Como defender o projeto para um professor

Defesa conservadora:

1. O nucleo do TCC e forecasting consolidado de demanda/exposição, alinhado a demand-based asset pricing.
2. CONS e SH medem exposição em valor por gestora, ação e mes.
3. CDA reconstrói, em apendice, a rede fundo->fundo apagada pela CONS.
4. O tratamento de dados foi auditado: formatos, duplicatas, joins, PL, tickers, preços e arestas.
5. A pergunta de previsão foi testada com benchmark forte, n-1, fatores, bootstrap por mes e sem vazamento.
6. A primeira feature de rede nao melhora, e isso vira baseline disciplinado para uma extensao com modelo de grafo.

## 11. Figuras e tabelas para apresentar ao orientador

Ordem sugerida para a reunião:

1. `stock_crowding_top15.png`: mostra que a demanda institucional se concentra em blue chips.
2. Tabela `exposure_definitions_comparison.csv`: mostra exposição em R$ e US$ para ITUB4 nas definições direta, long e net.
3. `pos_usd_top_gestoras.png`: mostra a série de exposição em valor por gestora.
4. Tabela `cda_edges_summary.csv`: mostra que a CDA tem massa suficiente para reconstruir rede fundo->fundo.
5. `research_design_graph.png`: mostrar que o nucleo e forecast consolidado e a CDA fica no apendice.
6. `cda_graph_fund_core.png` e `cda_graph_manager_projection.png`: mostrar visualmente a rede CDA.
7. Tabela `graph_structural_by_month.csv`: destacar 0 meses com ciclos, profundidade mediana 7 e max 9.
8. `itub4_dedup_itau.png` e `itub4_dedup_summary.csv`: mostrar duplicação intra-gestora.
9. `forecast_round3_skill.png`: mostrar que nivel em valor tem alguma previsibilidade.
10. `forecast_consolidated_panel_metrics.csv`: mostrar que o painel amplo com n-1 e fator comum nao bate random walk.
11. `master_validation_checks.csv`: mostrar que a auditoria mestre passou sem FAIL.
12. `forecast_round4_metrics.csv`: mostrar que feature manual de rede ainda nao melhora, funcionando como baseline de extensao.
13. `forecast_quantity_delta_skill.png`: se perguntarem sobre quantidade, mostrar como robustez.

Mensagem de apresentação:

> O TCC mede exposição institucional consolidada em ações e tenta prever essa exposição por gestora e ação.
> A CDA fica no apendice: ela mostra a rede fundo-sobre-fundo que a CONS apaga, ajuda a entender risco de
> duplicação/aninhamento e deixa preparada uma extensao com modelos de grafo.

## 12. Checklist de reproducibilidade

Ordem minima:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/99_run_all.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/12_all_stocks.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/13_forecast_itub4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/14_forecast_round2.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/15_forecast_round3.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/17_forecast_round5.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/19_half_life.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/20_forecast_quantity.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/23_forecast_consolidated_panel.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/22_master_validation.R
```

Camada CDA/rede:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/_prep_fund_extracts.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/10_build_cda_edges.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/11_fund_graph.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/16_forecast_round4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/21_cda_graph_figures.R
```

Compilar TCC:

```powershell
Set-Location docs
pdflatex -interaction=nonstopmode tcc.tex
bibtex tcc
pdflatex -interaction=nonstopmode tcc.tex
pdflatex -interaction=nonstopmode tcc.tex
```

## 13. Pontos ainda sensiveis

- Confirmar a referencia bibliografica exata de `Replicant Investment Platforms`.
- Manter documentada a exclusão de BVMF3, VVAR11 e MLFT4 como séries degeneradas do forecast amplo.
- Decidir o desenho exato do modelo de grafo: nós=fundos ou gestoras; alvo=nível ou variação; horizonte=1, 3 ou 6 meses.
- Cuidar para nao vender GNN como promessa de ganho; ele deve ser testado contra baselines.

## 14. Frase final do projeto

O resultado mais defensavel e:

> Com CONS e SH, construimos um painel confiavel da exposição consolidada das gestoras a ações. A variação
> mensal da exposição e dificil de prever; o nivel em valor tem reversão a media em ITUB4 e em algumas blue
> chips, mas o painel amplo com n-1 e fator comum nao bate random walk. A CDA, documentada em apendice,
> reconstrói a rede fundo-sobre-fundo que a CONS apaga e prepara uma extensão com modelos de grafo para
> estudar risco e possíveis ganhos preditivos.
