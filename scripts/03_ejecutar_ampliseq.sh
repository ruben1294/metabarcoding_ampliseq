#!/usr/bin/env bash
# =============================================================================
#  03_ejecutar_ampliseq.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Ejecuta el pipeline nf-core/ampliseq. Lee las dos decisiones de
#  configuracion/parametros.sh (entorno y marcador) y lanza Nextflow con la
#  versión fija:
#    entorno  → perfil y recursos (-profile / -c recursos_<entorno>.config)
#    marcador → parámetros del análisis (-params-file marcador_<marcador>.yaml)
#  Guarda el comando exacto, el log y una copia de los parámetros usados.
#
#  Uso:   bash scripts/03_ejecutar_ampliseq.sh
#         bash scripts/03_ejecutar_ampliseq.sh --marcador its   (sobreescribe parametros.sh)
#         bash scripts/03_ejecutar_ampliseq.sh --dry-run   (solo prepara, no corre)
#         bash scripts/03_ejecutar_ampliseq.sh -y          (no pide confirmación)
# =============================================================================
set -euo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"

# Reutilizamos $SELLO para que la evidencia de la corrida comparta la marca de tiempo
source "scripts/lib/registro.sh"
source "scripts/lib/entorno.sh"
source "scripts/lib/marcador.sh"
iniciar_registro "03_ejecutar_ampliseq"

# Opciones de línea de comandos
# --marcador <its|16s|18s> sobreescribe el MARCADOR de parametros.sh solo para esta corrida
DRY_RUN="no"; ASUMIR_SI="no"
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)     DRY_RUN="si" ;;
        -y|--yes)      ASUMIR_SI="si" ;;
        -m|--marcador)
            shift; [ $# -gt 0 ] || { log_error "--marcador necesita un valor (its, 16s o 18s)"; exit 1; }
            MARCADOR="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" ;;
        --marcador=*)
            MARCADOR="$(printf '%s' "${1#*=}" | tr '[:upper:]' '[:lower:]')" ;;
        *) log_error "Argumento desconocido: '$1' (usa --marcador, --dry-run o -y)"; exit 1 ;;
    esac
    shift
done

# Definimos el entorno donde correrá el pipeline y el marcador a analizar
seleccionar_entorno    # fija MOTOR y CONFIG_RECURSOS
seleccionar_marcador   # fija CONFIG_MARCADOR (respeta el --marcador de arriba si se pasó)
activar_trap_errores

# Activamos el entorno con Nextflow y Java
if command -v conda >/dev/null 2>&1; then
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "$ENV_LANZADOR" 2>/dev/null \
        || { log_error "no existe el entorno '$ENV_LANZADOR'. Corre antes: bash scripts/00_instalar_dependencias.sh"; exit 1; }
fi
command -v nextflow >/dev/null 2>&1 || { log_error "Nextflow no disponible. Corre: bash scripts/00_instalar_dependencias.sh"; exit 1; }

# Guardamos cachés en el disco grande, para no llenar el disco del sistema
export NXF_SINGULARITY_CACHEDIR="$DIR_PROYECTO/.cache/singularity"
export NXF_CONDA_CACHEDIR="$DIR_PROYECTO/.cache/conda"
mkdir -p "$NXF_SINGULARITY_CACHEDIR" "$NXF_CONDA_CACHEDIR" "$DIR_LOGS" "$SALIDA"

# 1) Validaciones básicas
case "$MOTOR" in
    docker|singularity|apptainer|conda) : ;;
    *) log_error "MOTOR no válido: '$MOTOR' (usa docker, singularity, apptainer o conda)"; exit 1 ;;
esac

# Que el motor responda antes de empezar. En HPC el maestro (nodo5) solo manda
# las tareas a SLURM y el motor corre en los nodos de cómputo (nodo27, nodo28),
# así que aquí solo se exige 'sbatch'. En local el motor sí corre en esta máquina.
if [ "$ENTORNO" = "hpc" ]; then
    command -v sbatch >/dev/null 2>&1 \
        || { log_error "ENTORNO=hpc pero no encontré 'sbatch'. Lanza desde un nodo del clúster (p. ej. nodo5)."; exit 1; }
    case "$MOTOR" in
        docker)
            log_info "Docker corre en los nodos de cómputo (nodo27, nodo28); el maestro solo orquesta." ;;
        singularity|apptainer)
            command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 \
                || log_warn "MOTOR=$MOTOR: no veo Singularity/Apptainer en el maestro. Si Nextflow no puede preparar las imágenes, cárgalo con 'module load'." ;;
    esac
else
    case "$MOTOR" in
        docker)
            if ! docker info >/dev/null 2>&1; then
                log_error "MOTOR=docker pero Docker no responde. Abre Docker Desktop y activa la"
                log_error "  integración con esta distro: Settings → Resources → WSL integration."
                exit 1
            fi
            ;;
        singularity|apptainer)
            if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
                log_error "MOTOR=$MOTOR pero no encontré Singularity/Apptainer en el PATH."
                exit 1
            fi
            ;;
    esac
fi

# Existencia de los archivos de cada decisión
[ -f "$CONFIG_RECURSOS" ] || { log_error "no existe el archivo de recursos: $CONFIG_RECURSOS"; exit 1; }
[ -f "$CONFIG_MARCADOR" ] || { log_error "no existe el archivo de parámetros: $CONFIG_MARCADOR"; exit 1; }

# 2) Leemos lo necesario para validar y mostrar del archivo YAML
FW="$(leer_yaml FW_primer "$CONFIG_MARCADOR")"
RV="$(leer_yaml RV_primer "$CONFIG_MARCADOR")"
REGION="$(leer_yaml cut_its "$CONFIG_MARCADOR")"          # vacío en 16S y 18S
TAXONOMIA="$(leer_taxonomia "$CONFIG_MARCADOR")"          # PR2/DADA2, SILVA/QIIME2, etc.

[ -z "$FW" ] && { log_error "FW_primer vacío en $CONFIG_MARCADOR"; exit 1; }
[ -z "$TAXONOMIA" ] && log_warn "no hay base taxonómica activa en $CONFIG_MARCADOR (define dada_ref_taxonomy o qiime_ref_taxonomy)"
if [ "$DISENO_LECTURAS" = "paired" ] && [ -z "$RV" ]; then
    log_error "RV_primer vacío para diseño pareado. Revisa $CONFIG_MARCADOR"; exit 1
fi
if [ "$MARCADOR" = "its" ]; then
    case "$REGION" in
        its1|its2|full) : ;;
        *) log_error "cut_its inválido en $CONFIG_MARCADOR: '$REGION' (usa its1, its2 o full)"; exit 1 ;;
    esac
fi

# 3) Determinamos la entrada (samplesheet o carpeta)
ENTRADA=()
if [ "$USAR_SAMPLESHEET" = "si" ]; then
    [ -f "$SAMPLESHEET" ] || { log_error "no existe $SAMPLESHEET. Corre: bash scripts/01_generar_samplesheet.sh"; exit 1; }
    ENTRADA=( --input "$SAMPLESHEET" )
else
    ENTRADA=( --input_folder "$CARPETA_FASTQ" )
fi

# 4) Preparamos el params-file de la corrida: copia del YAML del marcador más los
#    toggles dinámicos. Los booleanos van aquí y no por CLI porque nf-schema los
#    valida estricto: un flag suelto (--illumina_pe_its) llega como string "true"
#    y la validación lo rechaza; en el YAML true es un booleano de verdad.
#    El archivo además queda como evidencia de lo que se corrió.
PARAMS_RUN="$SALIDA/params_usados_${SELLO}.yaml"
cp "$CONFIG_MARCADOR" "$PARAMS_RUN"
{
    echo ""
    echo "# Toggles añadidos por 03_ejecutar_ampliseq.sh (sello: $SELLO)"
    # Lecturas single-end (solo R1): sin esto ampliseq asume pareado y exige fastq_2
    if [ "$DISENO_LECTURAS" = "single" ]; then echo "single_end: true"; fi
    # Lecturas ITS pareadas: avisa a ampliseq del posible read-through
    if [ "$MARCADOR" = "its" ] && [ "$DISENO_LECTURAS" = "paired" ]; then echo "illumina_pe_its: true"; fi
    # Primers dobles (toggle de parametros.sh)
    if [ "$DOBLE_PRIMER" = "si" ]; then echo "double_primer: true"; fi
} >> "$PARAMS_RUN"

# 5) Ensamblamos el comando de Nextflow para correr el pipeline
#   recursos por -c (entorno) y parámetros por -params-file (marcador + toggles)
CMD=( nextflow run nf-core/ampliseq
      -r "$VERSION_PIPELINE"
      -profile "$MOTOR"
      -params-file "$PARAMS_RUN"
      -c "$CONFIG_RECURSOS"
      "${ENTRADA[@]}"
      --outdir "$SALIDA"
      -resume
      -ansi-log false )

# Metadatos (solo si existe el archivo)
[ -n "$METADATA" ] && [ -f "$METADATA" ] && CMD+=( --metadata "$METADATA" )
# Parámetros extra del usuario (avanzado)
if [ -n "$EXTRA_PARAMS" ]; then
    # shellcheck disable=SC2206
    CMD+=( $EXTRA_PARAMS )
fi

# 6) Mostramos el resumen
cabecera_registro "EJECUCIÓN DE nf-core/ampliseq. Proyecto: $PROYECTO"
log_info "  Pipeline:        nf-core/ampliseq r${VERSION_PIPELINE}"
log_info "  Entorno:         $ENTORNO  (recursos: $CONFIG_RECURSOS)"
log_info "  Marcador:        $MARCADOR  (parámetros: $CONFIG_MARCADOR → $PARAMS_RUN)"
log_info "  Motor:           $MOTOR"
log_info "  Entrada:         ${ENTRADA[*]}"
log_info "  Primers:         FW=$FW${RV:+  RV=$RV}"
[ "$MARCADOR" = "its" ] && log_info "  Región ITS:      $REGION"
log_info "  Taxonomía:       $TAXONOMIA"
log_info "  Metadatos:       ${METADATA:-(ninguno)}"
log_info "  Salida:          $SALIDA"
log_info "  Comando completo:"
log_info "    ${CMD[*]}"
log_info "=========================================================================="

# Guardamos el comando exacto, para efectos de reproducibilidad y trazabilidad
echo "${CMD[*]}" > "$DIR_LOGS/comando_${SELLO}.txt"

if [ "$DRY_RUN" = "si" ]; then
    log_info "[--dry-run] Todo preparado. No se ejecutó Nextflow."
    log_info "Para correr de verdad: bash scripts/03_ejecutar_ampliseq.sh"
    exit 0
fi

# 7) Confirmación de marcador y primers
# Solo pregunta si hay terminal y no se pasó -y, para no lanzar el análisis con
# valores por defecto sin confirmarlos con quien hizo la secuenciación.
if [ "$ASUMIR_SI" != "si" ] && [ -t 0 ]; then
    echo
    read -r -p "¿Confirmas MARCADOR=$MARCADOR y PRIMERS FW=$FW${RV:+ RV=$RV}? [s/N] " RESP
    case "${RESP:-}" in
        s|S|si|SI|Si|y|Y|yes) : ;;
        *) log_warn "Cancelado por el usuario. Ajusta la configuración y vuelve a intentarlo."; exit 0 ;;
    esac
fi

# 8) Ejecutamos y registramos el log
log_info "Lanzando Nextflow… (el log se guarda en $LOG_OUT y $LOG_ERR)"
"${CMD[@]}" # Este comando es el que corre todo el pipeline

log_info "=========================================================================="
log_info "Análisis terminado"
log_info "   Resultados:  $SALIDA/"
log_info "   Reporte:     $SALIDA/multiqc/  y  $SALIDA/summary_report/"
log_info "   Info de la corrida (versiones, tiempos): $SALIDA/pipeline_info/"
log_info "=========================================================================="
