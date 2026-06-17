# Guia tecnico detalhado do projeto

Este documento existe para explicar o projeto com mais granularidade do que o TCC. O TCC deve ser lido como
documento academico principal; este guia serve para entender decisões, bases, scripts, tratamentos,
resultados, limites e caminhos futuros.

## 1. Ideia em linguagem simples

O projeto mede quanto cada gestora brasileira esta exposta a ações. Primeiro fazemos isso para ITUB4, depois
para todas as ações reconheciveis na base. A pergunta de forecasting e: essa exposição e previsivel?

A resposta empirica e:

- A variação mensal da exposição e dificil de prever. O random walk e um benchmark forte.
- O nivel da exposição em algumas blue chips, como ITUB4, tem reversão a media.
- A reversão sugere que gestoras tem uma alocação-alvo para certas ações liquidas e muito detidas.
- A rede fundo-sobre-fundo, reconstruida via CDA, nao melhorou a previsão; ela e mais util para discutir
  risco e dupla contagem.

## 2. Estrutura atual da pasta `docs`

A pasta `docs` deve ter apenas:

- `tcc.tex`: fonte unica do TCC.
- `tcc.pdf`: PDF unico do TCC.
- `refs.bib`: bibliografia.
- `guia_tecnico_projeto.md`: este guia detalhado.

Arquivos antigos como `tcc_final`, `tcc_todas_acoes` e `tcc_forecasting` eram versões intermediarias e nao
devem permanecer como TCCs separados.

## 3. Fundamentação teorica

### 3.1 Koijen e Yogo

Koijen e Yogo desenvolvem uma abordagem de sistema de demanda para precificação de ativos. A ideia relevante
para este projeto e que carteiras institucionais observadas revelam demanda por ativos. Em vez de olhar
apenas para retornos ou fundamentos, o pesquisador observa as posições dos investidores e tenta entender a
estrutura da demanda.

No projeto, as gestoras sao as unidades de demanda. A posição de uma gestora em uma ação e a quantidade
empirica que usamos para estudar demanda institucional.

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

No projeto, GNN nao virou modelo central porque features simples de rede nao melhoraram a previsão. Antes de
implementar uma GNN pesada, testamos se a exposição dos vizinhos no grafo acrescentava sinal. Nao acrescentou.

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

A CDA nao e necessaria para construir o painel principal de exposição. Ela e usada no apendice para estudar
estrutura fundo-sobre-fundo e dupla contagem.

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

### 5.8 Deltas gap-safe

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
e, se a CDA estiver disponivel, de-duplicação complementar.

### 6.8 Forecasting

Scripts:

- `R/13_forecast_itub4.R`: rodada 1, variação mensal ITUB4;
- `R/14_forecast_round2.R`: regularização, shrinkage, MAE e direção;
- `R/15_forecast_round3.R`: nivel da posição e horizontes 1, 3 e 6;
- `R/16_forecast_round4.R`: features de rede via CDA;
- `R/17_forecast_round5.R`: generalização do forecast de nivel para todas as ações;
- `R/19_half_life.R`: meia-vida da reversão a media.

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

### 7.2 Todas as ações

O painel reconhece 836 tickers. As ações detidas pelo maior numero de gestoras sao blue chips. Isso indica
concentração de demanda institucional em ativos liquidos e centrais no indice.

### 7.3 Forecast da variação

Resultado: sem previsibilidade robusta.

- AR nao bate random walk.
- PCA piora, especialmente com mais fatores.
- Direção fica perto de 50%.

Interpretação: variação mensal e muito ruidosa.

### 7.4 Forecast do nivel

Resultado: previsibilidade aparece no nivel da posição em US$.

- ITUB4: AR individual reduz RMSE em cerca de 10%.
- Peso nao tem o mesmo comportamento.
- Modelo de painel melhora em horizontes mais longos.

### 7.5 Half-life

O AR(1) no nivel estima velocidade de reversão a alocação-alvo.

Resultado:

- 36 de 37 gestoras revertem;
- rho mediano perto de 0,77;
- meia-vida mediana de 2,8 meses;
- pooled rho perto de 0,765;
- meia-vida pooled de 2,6 meses.

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

A CDA deve ficar no apendice porque:

- nao foi a base originalmente definida com o orientador;
- adiciona risco metodologico;
- exige explicar layout, confidencialidade, filtros, PL e de-duplicação;
- nao e necessaria para forecasting.

Mas ela nao deve ser descartada automaticamente porque:

- e a base correta para relações fundo->fundo;
- o Bloco 2 e exatamente cotas de fundos;
- a auditoria mostra valores plausiveis;
- o resultado de dupla contagem e economicamente relevante.

Formula segura:

> A CDA e uma extensão exploratoria, tecnicamente auditada, usada para investigar estruturas FIC/master e
> dupla contagem intra-gestora.

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

### 9.3 Por que nao foi priorizado

Antes de implementar GNN, o projeto testou uma feature de rede simples: exposição dos vizinhos. Essa feature
nao melhorou o AR de painel. Resultado:

- AR1 painel: skill 3,3%;
- rede painel: skill 3,1%;
- coeficiente de rede praticamente zero.

Isso sugere que uma GNN teria baixo retorno para previsão. Uma GNN poderia ser interessante por curiosidade
metodologica, mas nao deveria ser prioridade para o TCC.

### 9.4 Quando uma GNN faria sentido

Faria sentido se:

- o orientador quiser explicitamente um componente de machine learning;
- a CDA for aprovada como eixo do trabalho;
- houver tempo para documentar ambiente, arquitetura e validação;
- o objetivo for comparar metodologias, nao necessariamente melhorar muito a previsão.

### 9.5 Riscos de GNN

- painel curto: 72 meses;
- poucos nos se agregarmos por gestora;
- grafo CDA tem destinos externos;
- risco de overfitting;
- instalação de PyTorch/PyTorch Geometric pode consumir tempo;
- explicabilidade menor do que AR e half-life.

## 10. Como defender o projeto para um professor

Defesa conservadora:

1. O nucleo do TCC usa apenas CONS e SH, bases definidas no projeto.
2. O tratamento de dados foi auditado: formatos, duplicatas, joins, PL e tickers.
3. A pergunta de previsão foi testada com benchmark forte e sem vazamento.
4. O resultado negativo na variação mensal e informativo.
5. O resultado positivo no nivel e economicamente interpretavel como alocação-alvo.
6. A CDA nao e vendida como fundamento central; ela fica no apendice como extensão de risco.

## 11. Checklist de reproducibilidade

Ordem minima:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/99_run_all.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/12_all_stocks.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/13_forecast_itub4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/14_forecast_round2.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/15_forecast_round3.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/17_forecast_round5.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/19_half_life.R
```

Se a CDA for usada:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/_prep_fund_extracts.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/10_build_cda_edges.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/11_fund_graph.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/16_forecast_round4.R
```

Compilar TCC:

```powershell
Set-Location docs
pdflatex -interaction=nonstopmode tcc.tex
bibtex tcc
pdflatex -interaction=nonstopmode tcc.tex
pdflatex -interaction=nonstopmode tcc.tex
```

## 12. Pontos ainda sensiveis

- Confirmar com o Prof. Mauricio se a CDA deve ficar no apendice ou sair.
- Confirmar a referencia bibliografica exata de `Replicant Investment Platforms`.
- Decidir se os CSVs all-stocks modificados localmente devem ser commitados.
- Remover ou explicar séries degeneradas de tickers antigos/delistings no forecast de todas as ações.
- Evitar vender GNN como resultado necessário.

## 13. Frase final do projeto

O resultado mais defensavel e:

> Com CONS e SH, construimos um painel confiavel da exposição das gestoras a ações. A variação mensal da
> exposição e pouco previsivel, mas o nivel da posição em blue chips reverte a uma alocação-alvo. A CDA, em
> apendice, sugere que estruturas FIC/master podem gerar dupla contagem intra-gestora relevante, mas esse eixo
> deve ser validado separadamente com o orientador.
