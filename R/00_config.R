# =============================================================================
# 00_config.R — parâmetros centrais do pipeline
# Genérico por ticker; nesta fase testado SÓ para ITUB4.
# Rodar sempre a partir da RAIZ do projeto (ver R/99_run_all.R).
# =============================================================================

# --- Onde estão os CSV brutos da CVM (fora do git; ver data/raw/README.md) ---
# Use a variável de ambiente CVM_DATA_DIR para rodar em outra máquina sem editar
# o código. O caminho abaixo é mantido como fallback para a estação original.
DATA_DIR_DEFAULT <- "C:/Users/joaoz/Downloads/Consolidado_MF/Consolidado_MF"
DATA_DIR <- Sys.getenv("CVM_DATA_DIR", unset = DATA_DIR_DEFAULT)

# --- Período e ativo-alvo ---
YEARS         <- 2016:2021
TARGET_TICKER <- "ITUB4"

# --- Definição de exposição (parametrizável) -------------------------------
# "direta" = só participação direta
# "long"   = direta + cedida em empréstimo
# "net"    = direta + cedida + obrigações (estas entram negativas)  [PADRÃO]
EXPOSICAO <- "net"
# Definições geradas em paralelo (na dúvida, produzir 2+ versões). "direta" é
# exatamente a linha "ITAUUNIBANCO PN N1 - ITUB4". O painel primário = net.
EXPOSICOES <- c("direta", "long", "net")

# --- Consolidar entidades do mesmo grupo econômico numa única gestora? ------
CONSOLIDAR_GRUPOS <- TRUE

# --- PTAX (R$/US$): BCB SGS série 1, fim de mês -----------------------------
PTAX_SGS_SERIE <- 1L
PTAX_INI <- "01/01/2016"
PTAX_FIM <- "31/12/2021"

# --- Janela máxima (dias) entre meses consecutivos p/ delta "gap-safe" ------
GAP_MAX_DIAS <- 45

# --- Mínimo de observações p/ rodar ADF por gestora -------------------------
ADF_MIN_OBS <- 24L

# --- Diretórios de saída (relativos à raiz do projeto) ----------------------
OUT_PROC <- "data/processed"
OUT_TAB  <- "outputs/tables"
OUT_FIG  <- "outputs/figures"
for (d in c(OUT_PROC, OUT_TAB, OUT_FIG)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

# Cache dos extracts pesados (acelera reexecução; NÃO versionado) ------------
CACHE_LOAD <- file.path(OUT_PROC, "_cache_load.rds")
FORCE_RELOAD <- isTRUE(as.logical(Sys.getenv("FORCE_RELOAD", "FALSE")))
