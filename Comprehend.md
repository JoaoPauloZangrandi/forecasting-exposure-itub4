# Comprehend

Este arquivo e o mapa completo do projeto. A ideia e permitir que alguem abra o repositorio sem contexto,
entenda a pergunta de pesquisa, as bases, o pipeline, as escolhas metodologicas, os resultados e os pontos
que ainda precisam de cuidado em uma defesa academica.

## 1. Tese central do projeto

O TCC deve ser motivado como um exercicio de **forecasting consolidado de demanda/exposicao institucional
por acoes**.

A unidade central e:

```text
gestora x mes x acao
```

Para cada acao e mes, queremos medir:

- quais gestoras aumentaram exposicao;
- quais gestoras reduziram exposicao;
- se a exposicao futura de uma gestora pode ser prevista pelo seu proprio historico;
- se o comportamento do restante do mercado, isto e, as demais gestoras, acrescenta informacao;
- se, em uma extensao, a rede fundo-sobre-fundo ajuda a prever ou interpretar risco.

O ponto mais importante: **o alvo principal nao e prever a rede**. O alvo e prever a exposicao consolidada:

```text
E[g, i, t+h]
```

onde `g` e gestora, `i` e acao e `t+h` e o mes futuro. A rede CDA pode entrar como camada auxiliar, mas nao
muda o alvo.

## 2. Como interpretar a orientacao do Mauricio

Pelo que foi discutido com o orientador, o eixo mais defensavel e:

```text
forecasting de demanda/exposicao por gestora e acao
```

com motivacao em demand-based asset pricing.

Quando ele fala que "n-1 seria o restante do mercado", a leitura correta e:

```text
para prever a exposicao da gestora g em uma acao i, usar informacao das outras gestoras (-g) naquela acao.
```

Isso nao exige, no nucleo, reconstruir todos os caminhos fundo->fundo. A base CONS ja entrega a carteira
consolidada e portanto e suficiente para medir a exposicao final a acoes. A CDA entra no apendice para
entender a estrutura dos fundos sobre fundos que a CONS apaga.

## 3. O que e "exposicao" aqui

Exposicao e o valor da posicao da gestora em uma acao, agregado a partir dos fundos vinculados a ela.

Para ITUB4, o projeto usa tres definicoes:

- `direta`: apenas a linha direta de ITUB4;
- `long`: direta + acoes cedidas em emprestimo;
- `net`: long + obrigacoes por acoes recebidas em emprestimo, com sinal negativo.

A definicao principal e `net`, porque ela tenta capturar a exposicao economica liquida.

O valor da CONS esta em `Valor_Ativo_mil`, isto e, em mil reais. Para obter reais, multiplica-se por 1000.
Para converter para dolares, usa-se PTAX de fim de mes.

## 4. Valor versus quantidade de acoes

O orientador comentou que valor em reais e mais didatico para o leitor do que quantidade. Por isso, o TCC
deve manter **valor em R$ e US$ como medida principal**.

Mesmo assim, quantidade e uma robustez importante, porque valor mistura duas coisas:

```text
valor = quantidade x preco
```

Se o valor da exposicao sobe, isso pode acontecer porque a gestora comprou mais acoes ou porque o preco subiu.
Como a CONS nao informa quantidade, o projeto estima quantidade de ITUB4 por:

```text
q[g,t] = Valor_Ativo_mil[g,t] * 1000 / Preco_ITUB4[t]
```

Essa quantidade e estimada, nao observada diretamente. Ela e usada para ITUB4 porque baixamos e validamos
precos mensais oficiais da B3/COTAHIST.

## 5. Fundamentos teoricos

### 5.1 Koijen e Yogo

Koijen e Yogo sao a base de demand-based asset pricing usada aqui. A ideia geral e tratar carteiras
observadas como revelacao de demanda de investidores institucionais. Em vez de olhar apenas retornos,
fundamentos ou fatores agregados, o pesquisador olha para quem detem quais ativos.

No TCC:

```text
carteiras observadas -> demanda/exposicao institucional -> previsao de exposicao futura
```

### 5.2 Gabaix e Koijen

Gabaix e Koijen entram pela ideia de mercados inelasticos. Se a demanda por acoes e pouco elastica, fluxos e
mudancas de posicao de grandes investidores podem ter impacto desproporcional em precos.

No TCC, isso justifica olhar para:

- gestoras grandes;
- acoes muito detidas;
- blue chips com ownership institucional sobreposto;
- mudancas mensais de exposicao.

### 5.3 Greenwood e Thesmar

Greenwood e Thesmar tratam de fragilidade por propriedade comum. A ideia relevante e que ativos detidos por
investidores sujeitos a choques semelhantes podem ficar mais frageis. Se varias gestoras carregam as mesmas
acoes, e se elas ajustam posicoes de forma correlacionada, uma acao pode ficar mais exposta a choques de
fluxo.

No TCC, isso justifica medir crowding:

```text
quantas gestoras detem cada acao?
```

As acoes mais crowded no projeto sao blue chips como VALE3, PETR4, ITUB4 e BBDC4.

### 5.4 Artes e Barroso

Artes e Barroso entram como referencia metodologica para fatores/PCA. O projeto testa se existe um fator
comum de demanda/exposicao entre gestoras. O ponto tecnico importante e evitar vazamento:

```text
PCA deve ser estimado somente na janela de treino
```

### 5.5 Sanchez-Lengeling et al. e GNN

Sanchez-Lengeling et al. entram como introducao a graph neural networks. Uma GNN aprende representacoes de
nos usando atributos dos nos e conexoes do grafo.

No projeto, uma GNN faria sentido apenas como extensao:

- nos: gestoras ou fundos;
- arestas: relacoes fundo->fundo da CDA, possivelmente agregadas para gestora->gestora;
- atributos: exposicao atual, deltas, PL, centralidade, historico;
- alvo: exposicao consolidada futura.

O alvo nao seria "prever o grafo". O alvo continuaria sendo:

```text
E[g, i, t+h]
```

## 6. Bases de dados

### 6.1 CONS

CONS e a composicao consolidada de carteiras da CVM. Ela informa, para cada fundo, data e ativo, o valor
consolidado da posicao.

Caracteristicas importantes:

- periodo usado: 2016-2021;
- cerca de 21,1 milhoes de linhas;
- 100% das linhas tratadas aparecem como `Tipo_Ativo == "Acoes"`;
- valores em formato americano, com ponto decimal e eventualmente notacao cientifica;
- a carteira e consolidada: cotas de fundos sao "abertas" e viram ativos finais.

Consequencia:

```text
CONS e excelente para medir exposicao final a acoes.
CONS nao mostra o caminho FIC -> master -> ativo.
```

### 6.2 SH

SH e a serie historica dos fundos. Ela traz:

- CNPJ;
- codigo do fundo;
- gestora;
- patrimonio liquido;
- classificacao;
- data.

O PL vem em formato brasileiro, por exemplo `R$ 49.749,57`, entao precisa de parser diferente do parser da
CONS.

### 6.3 B3/COTAHIST

A B3/COTAHIST entra para obter o fechamento oficial mensal de ITUB4. Ela e usada para converter valor em
quantidade estimada de acoes:

```text
quantidade estimada = valor em reais / preco de fechamento mensal
```

O filtro usado e mercado a vista (`TPMERC=010`) e ultimo pregao de cada mes.

### 6.4 CDA

CDA e a Composicao e Diversificacao das Aplicacoes. A parte usada e o Bloco 2, que registra cotas de fundos.

Ela entra no projeto como apendice tecnico, nao como substituta da CONS.

Funcao da CDA:

- reconstruir arestas fundo->fundo;
- visualizar redes;
- testar ciclos;
- medir profundidade de aninhamento;
- estimar duplicacao intra-gestora;
- preparar uma possivel extensao com features de rede ou GNN.

## 7. Por que `read_csv("cad_fi.csv")` ficou ruim

Uma leitura simples como:

```r
library(readr)
a = read_csv("C:/Users/joaoz/Downloads/CDA/cad_fi.csv")
```

nao reproduz o tratamento do projeto.

Motivos:

1. O arquivo relevante nao e um cadastro generico, mas o historico anual da CDA.
2. A parte relevante e o Bloco 2: `cda_fi_BLC_2_AAAA.csv`.
3. Esse arquivo fica dentro de `cda_fi_AAAA.zip`.
4. O separador e `;`, nao virgula.
5. O encoding usado no script e `latin1`.
6. O projeto seleciona colunas especificas e filtra a origem para fundos do universo CONS+SH.

O script correto e:

```text
R/10_build_cda_edges.R
```

Ele baixa os ZIPs, abre o Bloco 2 de dentro do ZIP, le com `fread(..., sep = ";")`, normaliza CNPJs e salva:

```text
data/processed/cda_edges.csv
```

## 8. Pipeline de codigo

### 8.1 Configuracao e utilitarios

- `R/00_config.R`: define caminhos, anos, ticker principal, outputs.
- `R/01_utils.R`: funcoes para CNPJ, parsers numericos, ticker, escrita de tabelas.

### 8.2 Carregamento e painel principal

- `R/02_load_cons.R`: le CONS, remove duplicatas exatas, filtra ITUB4, classifica direta/cedida/obrigacao.
- `R/03_load_sh.R`: le SH, trata PL, gestora e classificacoes.
- `R/04_consolidate_groups.R`: consolida gestoras por grupo economico.
- `R/05_build_panel.R`: monta painel gestora x mes de ITUB4.
- `R/06_diagnostics.R`: gera auditorias.
- `R/07_correlation.R`: correlacoes entre gestoras.
- `R/08_load_prices.R`: baixa e trata B3/COTAHIST.
- `R/99_run_all.R`: roda o pipeline-base.

### 8.3 Todas as acoes

- `R/12_all_stocks.R`: extrai tickers e monta painel para todas as acoes.

Resultado:

- 836 tickers reconhecidos;
- painel gestora x mes x ticker;
- 238 acoes elegiveis para o forecast de nivel com historico suficiente.

### 8.4 Forecasting

- `R/13_forecast_itub4.R`: primeira rodada para ITUB4, delta da posicao em US$.
- `R/14_forecast_round2.R`: regularizacao, AR encolhido, MAE e direcao.
- `R/15_forecast_round3.R`: nivel da posicao e horizontes 1, 3 e 6 meses.
- `R/16_forecast_round4.R`: feature manual de rede via CDA.
- `R/17_forecast_round5.R`: forecast de nivel para todas as acoes elegiveis.
- `R/19_half_life.R`: meia-vida de reversao a media.
- `R/20_forecast_quantity.R`: robustez com quantidade estimada de ITUB4.

### 8.5 CDA e grafos

- `R/_prep_fund_extracts.R`: prepara extracts por fundo.
- `R/10_build_cda_edges.R`: baixa e processa CDA Bloco 2.
- `R/11_fund_graph.R`: calcula ciclos, profundidade e de-duplicacao intra-gestora.
- `R/21_cda_graph_figures.R`: gera imagens de grafo e diagrama do desenho empirico.

Figuras novas:

- `outputs/figures/research_design_graph.png`;
- `outputs/figures/cda_graph_fund_core.png`;
- `outputs/figures/cda_graph_manager_projection.png`.

## 9. Tratamentos criticos

### 9.1 CNPJ

Todo CNPJ e normalizado para digitos. Isso evita falhas de join por pontuacao.

### 9.2 Numeros

CONS e SH usam formatos diferentes. Isso e um ponto sensivel:

- CONS: formato americano;
- SH: formato brasileiro com `R$`, ponto de milhar e virgula decimal.

Usar o parser errado muda PL, exposicao e pesos.

### 9.3 Duplicatas exatas da CONS

A revisao encontrou duplicatas exatas em cerca de 0,2% das linhas. O impacto nos totais e pequeno, cerca de
0,01%, mas a correcao e metodologicamente correta.

A regra remove apenas linhas com mesmo:

```text
cnpj, codigo_fundo, data, nome_ativo, valor_mil
```

Lotes legitimos com valores diferentes sao preservados.

### 9.4 Variantes de exposicao

Para ITUB4:

- direta;
- cedida em emprestimo;
- obrigacao por acoes recebidas em emprestimo.

Primaria:

```text
net = direta + cedida + obrigacao
```

Obrigacoes entram com sinal negativo.

### 9.5 Grupos economicos

Gestoras sao consolidadas por grupo economico. Isso reduz ruido de nomes juridicos e deixa a unidade mais
interpretavel para o leitor.

### 9.6 Deltas mensais

Deltas sao calculados apenas para meses consecutivos. Isso evita criar variacao artificial quando ha lacuna.

### 9.7 Sem vazamento

Forecasting usa origem movel com janela expansivel. Em cada origem, o modelo so ve dados ate `t` e preve
`t+h`. PCA/fatores sao estimados dentro da janela de treino.

## 10. Resultados principais

### 10.1 ITUB4 em valor

O painel ITUB4 tem:

- 72 meses;
- 42 grupos economicos;
- 2.835 observacoes gestora-mes.

Em valor, o nivel da exposicao de ITUB4 tem alguma reversao a media. O AR individual reduz RMSE em torno de
10% contra random walk em horizontes curtos.

### 10.2 Variacao mensal

A variacao mensal e dificil de prever. Para valor e quantidade, os modelos simples quase nao superam o
random walk. Direcao fica perto de 50%, isto e, proxima de cara ou coroa.

Interpretacao:

```text
mudancas mensais de exposicao sao muito ruidosas.
```

### 10.3 Quantidade estimada

Quantidade estimada de ITUB4 mostra que parte da reversao observada em valor vem de preco/marcacao, nao
necessariamente de compra e venda previsivel de acoes.

Na variacao mensal da quantidade, o AR encolhido melhora pouco em RMSE e piora em MAE. No nivel, o ganho e
mais fraco do que em valor.

### 10.4 Todas as acoes

O forecast de nivel em valor foi repetido para acoes elegiveis. A previsibilidade nao e geral:

- 238 acoes avaliaveis;
- mediana de skill negativa;
- ITUB4 fica entre os casos mais previsiveis;
- o sinal e mais forte em blue chips muito detidas.

Isso e coerente com a literatura: os papeis crowded sao justamente os mais relevantes para demanda
institucional e risco.

## 11. CDA: resultados tecnicos

### 11.1 Massa de dados

A CDA processada tem:

- 835.694 arestas fundo->fundo entre 2016 e 2021;
- 72 meses;
- destino vazio igual a zero;
- `DT_CONFID_APLIC` preenchido em parte das linhas, mas com `CNPJ_FUNDO_COTA` disponivel.

### 11.2 Grafos

Em dezembro de 2021, a rede CDA processada usada nas figuras tinha:

- 5.045 nos;
- 19.191 arestas;
- subgrafo visual com 96 nos e 258 arestas;
- projecao gestora->gestora com 38 grupos e 45 arestas intergestoras.

### 11.3 Ciclos

No subgrafo intra-amostra, todos os 72 meses sao DAGs. Ou seja, nao foram encontrados ciclos diretos.

Isso responde a preocupacao de estruturas circulares.

### 11.4 Profundidade

Apesar de nao haver ciclos, ha aninhamento:

- profundidade maxima mediana: 7;
- profundidade maxima observada: 9.

### 11.5 De-duplicacao intra-gestora

Formula:

```text
dedup_g = soma_i L_i - soma_{A->B dentro da mesma gestora} phi_AB * L_B
```

onde:

```text
phi_AB = valor_A_em_B / PL_B
```

Resultado para ITUB4:

- duplicacao intra-gestora estimada: 37,6%;
- Itau: cerca de 41,7%;
- incluindo arestas rastreaveis entre gestoras, o numero chega perto de 43,0%, mas esse nao e o indicador
  principal.

## 12. Como explicar a CDA em uma reuniao

Frase segura:

```text
A CONS e a base principal porque mede exposicao final consolidada a acoes. A CDA entra no apendice porque
ela mostra a rede fundo-sobre-fundo que a CONS apaga. Eu nao uso CDA para substituir a CONS; uso para
entender estrutura, duplicacao, circularidade e para deixar preparada uma extensao com modelos de grafo.
```

Frase a evitar:

```text
Estamos prevendo os grafos.
```

Melhor:

```text
Estamos prevendo exposicao consolidada. O grafo pode ser usado como informacao auxiliar em uma extensao.
```

## 13. Como uma GNN entraria corretamente

Uma GNN so deve entrar depois de o baseline consolidado estar claro.

### 13.1 Nodes

Possibilidades:

- gestoras;
- fundos;
- gestora-acao;
- fundo-acao.

Mais simples e defensavel:

```text
nos = gestoras
```

### 13.2 Edges

Edges viriam da CDA, agregadas de fundo->fundo para gestora->gestora.

Exemplo:

```text
edge g1 -> g2 existe se fundos de g1 detem cotas de fundos de g2
```

### 13.3 Features

Features possiveis:

- exposicao atual em valor;
- delta passado;
- exposicao do restante do mercado;
- PL agregado da gestora;
- grau de entrada/saida;
- centralidade;
- exposicao media dos vizinhos.

### 13.4 Target

Target:

```text
E[g, i, t+h]
```

ou:

```text
Delta E[g, i, t+h]
```

O alvo preferivel para comecar e nivel em valor, porque foi onde apareceu previsibilidade.

### 13.5 Validacao

Precisa ser out-of-sample com origem movel. Nao pode embaralhar meses aleatoriamente, porque isso vazaria
informacao temporal.

Comparar contra:

- random walk;
- AR;
- painel;
- PCA/fatores;
- feature manual de rede.

## 14. Riscos metodologicos

Pontos que um professor PhD olharia:

1. **Unidade de medida**: CONS em mil reais; CDA em reais; SH PL em formato brasileiro.
2. **Look-ahead bias**: PCA, parametros e features precisam ser calculados apenas com dados de treino.
3. **CDA fora do nucleo**: nao vender CDA como base principal se a pergunta e forecasting consolidado.
4. **Quantidade estimada**: nao chamar de quantidade observada.
5. **Ticker changes/delistings**: cuidado no forecast de todas as acoes.
6. **De-duplicacao**: deixar claro que 37,6% e intra-gestora, nao duplicacao total do sistema.
7. **GNN**: nao vender como promessa de ganho; tem que bater baseline.
8. **N-1**: deixar claro que significa restante do mercado, nao necessariamente grafo.

## 15. Como reproduzir

Pipeline-base:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/99_run_all.R
```

Todas as acoes:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/12_all_stocks.R
```

Forecasting:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/13_forecast_itub4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/14_forecast_round2.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/15_forecast_round3.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/16_forecast_round4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/17_forecast_round5.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/19_half_life.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/20_forecast_quantity.R
```

CDA e grafos:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/_prep_fund_extracts.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/10_build_cda_edges.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/11_fund_graph.R
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

## 16. Arquivos finais para olhar

- `docs/tcc.pdf`: TCC consolidado.
- `docs/tcc.tex`: fonte LaTeX.
- `docs/guia_tecnico_projeto.md`: guia tecnico resumido.
- `Comprehend.md`: este documento detalhado.
- `outputs/figures/research_design_graph.png`: desenho empirico.
- `outputs/figures/cda_graph_fund_core.png`: subgrafo real CDA.
- `outputs/figures/cda_graph_manager_projection.png`: projecao gestora->gestora.
- `outputs/tables/cda_edges_summary.csv`: resumo CDA.
- `outputs/tables/graph_structural_by_month.csv`: ciclos e profundidade.
- `outputs/tables/forecast_round4_metrics.csv`: teste da feature manual de rede.

## 17. Mensagem final do projeto

Forma curta:

```text
O TCC mede exposicao consolidada de gestoras a acoes e testa se essa exposicao e previsivel. A literatura de
demand-based asset pricing motiva olhar para carteiras institucionais como demanda observada. A CONS e SH
constroem o painel principal. A previsao mensal da variacao e dificil, mas o nivel em valor mostra alguma
reversao a media, principalmente em blue chips. A CDA entra em apendice para documentar a rede fundo-sobre-
fundo que a CONS apaga, avaliar risco de aninhamento/duplicacao e preparar uma extensao com modelos de grafo.
```

