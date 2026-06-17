# Forecasting da exposição de gestoras de ações e o risco de estruturas fundo-sobre-fundo

Trabalho de Conclusão de Curso (FGV EESP) — orientador Prof. Maurício Ferraresi Jr.

O objetivo central é **medir e inferir o risco de estruturas "fundo-sobre-fundo"** (fundos de
cotas que investem em outros fundos que detêm ações) no mercado brasileiro, usando como **lente
a exposição das gestoras a ações**. O método é validado com **uma ação (ITUB4 — Itaú Unibanco PN)**
antes de estender para as demais. A motivação teórica vem de *demand-based asset pricing*: os preços
se formam em parte pela demanda dos investidores institucionais, que tem estrutura (inércia,
co-movimento) e, portanto, é parcialmente previsível — e estruturas aninhadas de fundos podem
**amplificar ou propagar choques**.

**Período:** 2016–2021 (carteiras mensais).

## Estrutura

```
data/raw/          CSV originais da CVM — NÃO versionados (ver data/raw/README.md)
data/processed/    bases tratadas versionadas e extracts grandes regeneráveis
R/                 pipeline modular em R
  00_config.R          parâmetros (DATA_DIR, anos, ticker, modo de exposição, grupos)
  01_utils.R           parsers e helpers (número, CNPJ, ticker, desacentuação)
  02_load_cons.R       carrega CONS por ano; ITUB4 por variante (direta/cedida/obrigação) e fundo-mês
  03_load_sh.R         carrega SH; PL, gestora, universo mensal; auditorias
  04_consolidate_groups.R  consolidação robusta de grupos econômicos
  05_build_panel.R     painel gestora×mês: posição R$ e US$ (PTAX), peso, deltas, ADF
  06_diagnostics.R     validação dos fatos das bases + cobertura + duplicação FIC
  07_correlation.R     matrizes de correlação entre gestoras + heatmap
  99_run_all.R         orquestra os módulos-base de exposição (só ITUB4)
  10_build_cda_edges.R     baixa a CDA Bloco 2 e extrai arestas fundo->fundo
  11_fund_graph.R          sumariza a rede fundo-sobre-fundo
  12_all_stocks.R          generaliza o painel e a de-duplicação para todas as ações
  13_forecast_itub4.R      primeira rodada de forecasting para ITUB4
  14_forecast_round2.R     robustez: PCA menor, AR encolhido, MAE e direção
  15_forecast_round3.R     previsibilidade de nível e horizontes 1/3/6 meses
  16_forecast_round4.R     teste de features de rede no forecast
  17_forecast_round5.R     forecast de nível para todas as ações elegíveis
  18_data_review.R         revisão profunda das bases e auditorias
  19_half_life.R           meia-vida de reversão à alocação-alvo
  forecasting_scaffold.R   esqueleto histórico; não é usado no pipeline atual
docs/              tcc.tex, refs.bib e tcc.pdf
notebooks/         exploração
outputs/figures/   gráficos (.png)
outputs/tables/    tabelas de auditoria (.csv)
```

## Dados

Origem: CVM. Duas bases por ano (2016–2021), formato `;`, UTF-8. Os arquivos brutos
ficam fora do git. O caminho padrão está em `R/00_config.R`, mas pode ser sobrescrito
sem editar o código via variável de ambiente `CVM_DATA_DIR`.

- **CONS** (`cons_YYYY.csv`): composição consolidada de carteiras (fundo × mês × ativo). Números
  em **formato americano** (ponto decimal, inclusive notação científica) — parse robusto; 22 linhas
  (em ~21 mi) com aspas malformadas em nomes de ações fechadas viram `NA` (não-ITUB4). **100%
  `Tipo_Ativo == "Ações"`** (a consolidação da CVM dissolveu as cotas em ações — ver "Limitação").
- **SH** (`SH_YYYY.csv`): série histórica (fundo × dia). Traz **GESTORA** e **PL**. Números em
  **formato brasileiro** (`R$ 49.749,57`), data `dd/mm/aaaa`.

Chave de ligação: `Código` (CONS) == `COD_FUNDO` (SH) para o mesmo CNPJ.

## Decisões metodológicas (travadas com o orientador)

1. **Unidade:** gestora, consolidada por grupo econômico (Itaú, BTG, XP, ...).
2. **Medida:** **valor** (não quantidade), em **R$ e em US$** (PTAX fim de mês, BCB SGS série 1).
3. **Exposição:** três definições geradas em paralelo — **direta** (só `ITAUUNIBANCO PN N1 - ITUB4`), **long** (+ cedida em empréstimo) e **net** (+ obrigações, negativas). Primária = **net**; todas exportadas (`painel_itub4_{direta,long,net}.csv`).
4. **Modelar a posição** (em R$/US$), que é não-estacionária → diferenciar; **não diferenciar o peso**
   (estacionário). Rodar ADF e reportar.
5. **Manter os FICs** — a estrutura aninhada é o objeto de estudo, não ruído.

## Limitação crítica

A CONS é **100% "Ações"**: as relações fundo→fundo foram apagadas pela consolidação. Para montar o
grafo fundo-sobre-fundo (detecção de ciclos, profundidade, peso indireto) é preciso a base **CDA não
consolidada** da CVM (bloco BLC_2 de "Cotas de Fundos").

**Atualização:** a CDA Bloco 2 (2016–2021) já foi baixada e as arestas fundo→fundo extraídas
(`R/10_build_cda_edges.R` → `data/processed/cda_edges.csv`, fora do git). Das cotas com origem nos
nossos fundos, ~33% têm destino na amostra, ~32% são **confidenciais** (a CVM mascara o destino) e
~35% apontam para fundos **externos** — o que delimita até onde o look-through é rastreável.

## Como rodar

R 4.5.1 (fora do PATH nesta máquina). Pacotes usados: `data.table`, `stringr`, `jsonlite`,
`ggplot2`, `tseries` e `igraph`.

```r
install.packages(c("data.table", "stringr", "jsonlite", "ggplot2", "tseries", "igraph"))
```

Se os dados brutos estiverem em outra pasta:

```powershell
$env:CVM_DATA_DIR = "D:\dados_cvm\Consolidado_MF"
```

Pipeline-base de ITUB4:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/99_run_all.R
```

Extensão para todas as ações, rede e forecast:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/10_build_cda_edges.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/_prep_fund_extracts.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/12_all_stocks.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/13_forecast_itub4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/14_forecast_round2.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/15_forecast_round3.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/16_forecast_round4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/17_forecast_round5.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/18_data_review.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/19_half_life.R
```

Compilar o documento (MiKTeX **sem Perl** → usar `pdflatex`+`bibtex`, não `latexmk`):

```powershell
Set-Location docs
pdflatex -interaction=nonstopmode tcc.tex; bibtex tcc; pdflatex -interaction=nonstopmode tcc.tex; pdflatex -interaction=nonstopmode tcc.tex
```

## Status

Fase atual: pipeline de exposição validado para ITUB4, extensão para todas as ações, revisão profunda
das bases, de-duplicação de estruturas fundo-sobre-fundo e rodadas de forecasting já executadas.

Resultado central das rodadas de previsão: a variação mensal da posição em ITUB4 é difícil de bater
contra random walk; a previsibilidade aparece melhor no **nível** da exposição, com reversão à média
e meia-vida interpretável. Na rodada com todas as ações, ITUB4 fica entre as ações com skill positivo
do AR contra random walk, mas o sinal é heterogêneo por ticker. As features de rede foram testadas
como preditor incremental e não acrescentaram ganho material sobre o AR de painel na especificação
atual.
