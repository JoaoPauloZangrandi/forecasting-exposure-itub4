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
data/processed/    bases tratadas (painel_itub4.csv)
R/                 pipeline modular em R
  00_config.R          parâmetros (DATA_DIR, anos, ticker, modo de exposição, grupos)
  01_utils.R           parsers e helpers (número, CNPJ, ticker, desacentuação)
  02_load_cons.R       carrega CONS por ano; exposição NET em ITUB4 por fundo-mês
  03_load_sh.R         carrega SH; PL, gestora, universo mensal; auditorias
  04_consolidate_groups.R  consolidação robusta de grupos econômicos
  05_build_panel.R     painel gestora×mês: posição R$ e US$ (PTAX), peso, deltas, ADF
  06_diagnostics.R     validação dos fatos das bases + cobertura + duplicação FIC
  07_correlation.R     matrizes de correlação entre gestoras + heatmap
  99_run_all.R         orquestra todos os módulos (só ITUB4)
  forecasting_scaffold.R   esqueleto de PCA/AR/VAR/GNN — NÃO É EXECUTADO
docs/              tcc.tex, refs.bib e tcc.pdf
notebooks/         exploração
outputs/figures/   gráficos (.png)
outputs/tables/    tabelas de auditoria (.csv)
```

## Dados

Origem: CVM. Duas bases por ano (2016–2021), formato `;`, UTF-8:

- **CONS** (`cons_YYYY.csv`): composição consolidada de carteiras (fundo × mês × ativo). Números
  em **formato americano** (ponto decimal, inclusive notação científica) — parse direto com
  `as.numeric()`. **100% `Tipo_Ativo == "Ações"`** (a consolidação da CVM dissolveu as cotas em
  ações — ver "Limitação" abaixo).
- **SH** (`SH_YYYY.csv`): série histórica (fundo × dia). Traz **GESTORA** e **PL**. Números em
  **formato brasileiro** (`R$ 49.749,57`), data `dd/mm/aaaa`.

Chave de ligação: `Código` (CONS) == `COD_FUNDO` (SH) para o mesmo CNPJ.

## Decisões metodológicas (travadas com o orientador)

1. **Unidade:** gestora, consolidada por grupo econômico (Itaú, BTG, XP, ...).
2. **Medida:** **valor** (não quantidade), em **R$ e em US$** (PTAX fim de mês, BCB SGS série 1).
3. **Exposição:** **NET = direta + cedida em empréstimo + obrigações (negativa)** (parametrizável).
4. **Modelar a posição** (em R$/US$), que é não-estacionária → diferenciar; **não diferenciar o peso**
   (estacionário). Rodar ADF e reportar.
5. **Manter os FICs** — a estrutura aninhada é o objeto de estudo, não ruído.

## Limitação crítica

A CONS é **100% "Ações"**: as relações fundo→fundo foram apagadas pela consolidação. Para montar o
grafo fundo-sobre-fundo (detecção de ciclos, profundidade, peso indireto) é preciso a base **CDA não
consolidada** da CVM (bloco BLC de "Cotas de Fundos"). O plano para obtê-la está documentado no TCC.

## Como rodar

R 4.5.1 (fora do PATH nesta máquina):

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R/99_run_all.R
```

Compilar o documento:

```powershell
latexmk -pdf -cd docs/tcc.tex
```

## Status

Fase atual: setup, validação das bases, pipeline da exposição (ITUB4) e documento. **Os modelos de
forecasting (PCA/GNN) estão preparados mas NÃO foram executados** — aguardando autorização.
