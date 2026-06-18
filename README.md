# Forecasting da exposição de gestoras de ações

Trabalho de Conclusão de Curso (FGV EESP) — orientador Prof. Maurício Ferraresi Jr.

O objetivo central é **medir e prever a exposição das gestoras a ações** no mercado brasileiro, motivado pela
literatura de *demand-based asset pricing*. O desenho atual é um sistema de forecasting por gestora e ação:
para cada ação, mês a mês, medir quem aumentou ou reduziu exposição e testar se o histórico da gestora, o
restante do mercado e a rede de fundos interconectados ajudam a prever a exposição futura.

A medida principal é **exposição em valor** (R$ e US$), por ser mais didática e diretamente ligada a risco
patrimonial. A quantidade estimada de ações entra como robustez para ITUB4. A CDA Bloco 2 é usada para
reconstruir relações fundo→fundo e formar a camada de rede do sistema preditivo.

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
  05_build_panel.R     painel gestora×mês: posição R$/US$, quantidade estimada, peso, deltas, ADF
  06_diagnostics.R     validação dos fatos das bases + cobertura
  07_correlation.R     matrizes de correlação entre gestoras + heatmap
  08_load_prices.R     baixa COTAHIST/B3 e gera preços mensais de ITUB4
  99_run_all.R         orquestra os módulos-base de exposição (só ITUB4)
  10_build_cda_edges.R     camada CDA/rede: baixa Bloco 2 e extrai arestas fundo->fundo
  11_fund_graph.R          camada CDA/rede: sumariza a rede fundo-sobre-fundo
  12_all_stocks.R          generaliza o painel para todas as ações; de-dup por CDA é complementar
  13_forecast_itub4.R      primeira rodada de forecasting para ITUB4
  14_forecast_round2.R     robustez: PCA menor, AR encolhido, MAE e direção
  15_forecast_round3.R     previsibilidade de nível e horizontes 1/3/6 meses
  16_forecast_round4.R     teste de features de rede no forecast
  17_forecast_round5.R     forecast de nível para todas as ações elegíveis
  18_data_review.R         revisão profunda das bases e auditorias
  19_half_life.R           meia-vida de reversão à alocação-alvo
  20_forecast_quantity.R   forecasting usando quantidade estimada de ITUB4
  forecasting_scaffold.R   esqueleto histórico; não é usado no pipeline atual
docs/              tcc.tex/pdf (TCC único), refs.bib e guia_tecnico_projeto.md
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

## Decisões metodológicas atuais

1. **Unidade:** gestora, consolidada por grupo econômico (Itaú, BTG, XP, ...).
2. **Medidas:** **valor** em R$/US$ como medida principal de exposição e risco; **quantidade estimada de
   ações** como robustez para separar preço e quantidade em ITUB4. A quantidade é
   `Valor_Ativo_mil * 1000 / fechamento_ITUB4_B3`.
3. **Exposição:** três definições geradas em paralelo — **direta** (só `ITAUUNIBANCO PN N1 - ITUB4`), **long** (+ cedida em empréstimo) e **net** (+ obrigações, negativas). Primária = **net**; todas exportadas (`painel_itub4_{direta,long,net}.csv`).
4. **Modelagem:** prever nível e variação da exposição. O nível em R$/US$ captura risco patrimonial; a
   variação mensal testa aumento/redução de exposição.
5. **Manter os FICs** — a estrutura aninhada é o objeto de estudo, não ruído.

## CDA e rede de fundos

A CONS é **100% "Ações"**: as relações fundo→fundo foram apagadas pela consolidação. Por isso, qualquer
análise explícita de grafo fundo-sobre-fundo precisa de uma base adicional. A opção usada aqui é a **CDA não
consolidada** da CVM, Bloco BLC_2 de "Cotas de Fundos".

A CDA Bloco 2 (2016–2021) já foi baixada e as arestas fundo→fundo extraídas
(`R/10_build_cda_edges.R` → `data/processed/cda_edges.csv`, fora do git). Ela serve para: (i) testar se há
circularidade nas estruturas FIC/master; (ii) medir profundidade de aninhamento; (iii) estimar dupla contagem
intra-gestora; e (iv) criar features de rede para forecasting. No arquivo histórico processado, o campo
`DT_CONFID_APLIC` aparece preenchido em parte das arestas, mas `CNPJ_FUNDO_COTA` está disponível; portanto,
não tratar essas linhas automaticamente como destino mascarado.

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

Extensão para todas as ações e forecast:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/12_all_stocks.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/13_forecast_itub4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/14_forecast_round2.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/15_forecast_round3.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/16_forecast_round4.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/17_forecast_round5.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/18_data_review.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/19_half_life.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/20_forecast_quantity.R
```

Camada de rede/CDA:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/_prep_fund_extracts.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/10_build_cda_edges.R
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/11_fund_graph.R
```

Compilar o documento (MiKTeX **sem Perl** → usar `pdflatex`+`bibtex`, não `latexmk`):

```powershell
Set-Location docs
pdflatex -interaction=nonstopmode tcc.tex; bibtex tcc; pdflatex -interaction=nonstopmode tcc.tex; pdflatex -interaction=nonstopmode tcc.tex
```

Para entender o projeto em nível operacional, use `docs/guia_tecnico_projeto.md`.

## Status

Fase atual: pipeline de exposição validado para ITUB4, extensão para todas as ações, revisão profunda das
bases CONS+SH+CDA, rodadas de forecasting e primeira feature de rede executadas.

Resultado central: o projeto deve ser motivado como forecasting de demanda/exposição. A variação mensal é
difícil de bater contra random walk; o nível em valor tem alguma reversão à média; e a rede CDA é a
infraestrutura para avançar para modelos de grafo. A primeira feature manual de vizinhos não melhora o AR de
painel, então ela funciona como baseline, não como conclusão contra GNN.
