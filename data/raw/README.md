# data/raw — dados brutos da CVM (NÃO versionados)

Os CSV originais (~4,2 GB) **não entram no git** (ver `.gitignore`). Eles ficam em:

```
C:\Users\joaoz\Downloads\Consolidado_MF\Consolidado_MF\
```

e são referenciados por `DATA_DIR` em `R/00_config.R`. Arquivos esperados (12):

- `cons_2016.csv` … `cons_2021.csv` (composição consolidada de carteiras)
- `SH_2016.csv` … `SH_2021.csv` (série histórica: gestora + PL)

Para usar outra máquina/pasta, basta editar `DATA_DIR` em `R/00_config.R`.
