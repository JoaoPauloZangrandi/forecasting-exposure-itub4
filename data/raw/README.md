# data/raw — dados brutos da CVM (NÃO versionados)

Os CSV originais (~4,2 GB) **não entram no git** (ver `.gitignore`). Eles ficam em:

```
C:\Users\joaoz\Downloads\Consolidado_MF\Consolidado_MF\
```

e são referenciados por `DATA_DIR` em `R/00_config.R`. Para rodar em outra
máquina sem editar o código, defina a variável de ambiente `CVM_DATA_DIR`.
Arquivos esperados (12):

- `cons_2016.csv` … `cons_2021.csv` (composição consolidada de carteiras)
- `SH_2016.csv` … `SH_2021.csv` (série histórica: gestora + PL)

Exemplo no PowerShell:

```powershell
$env:CVM_DATA_DIR = "D:\dados_cvm\Consolidado_MF"
```

Sem essa variável, o pipeline usa o caminho padrão configurado em `R/00_config.R`.
