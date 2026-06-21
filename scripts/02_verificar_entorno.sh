#!/usr/bin/env bash
# =============================================================================
#  02_verificar_entorno.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Revisa que todo lo que el flujo necesita esté listo, sin instalar ni cambiar
#  nada: herramientas, versiones, datos de entrada y configuración.
#
#  Uso:   bash scripts/02_verificar_entorno.sh
#         bash scripts/02_verificar_entorno.sh --proyecto corrida2  (sobreescribe parametros.sh)
#         bash scripts/02_verificar_entorno.sh --help      (muestra la ayuda)
# =============================================================================
set -uo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Si no podemos entrar al proyecto, nada más funciona (no se leerían parametros.sh
# ni las libs).
cd "$DIR_PROYECTO" || { echo "ERROR: no pude entrar al directorio del proyecto: $DIR_PROYECTO" >&2; exit 1; }
source "configuracion/parametros.sh"

source "scripts/lib/registro.sh"
source "scripts/lib/entorno.sh"
source "scripts/lib/marcador.sh"

# Ayuda de la línea de comandos
mostrar_ayuda() {
    cat <<'AYUDA'
Uso: bash scripts/02_verificar_entorno.sh [opciones]

Revisa que el entorno esté listo (herramientas, datos y configuración) según
configuracion/parametros.sh, sin instalar ni cambiar nada. La opción de abajo
sobreescribe, solo para esta corrida, lo definido en parametros.sh.

Opciones:
  -p, --proyecto <nombre>      Nombre del proyecto. Sobreescribe PROYECTO de
                               parametros.sh (y con él la carpeta de logs).
  -h, --help                   Muestra esta ayuda y termina.

Ejemplos:
  bash scripts/02_verificar_entorno.sh
  bash scripts/02_verificar_entorno.sh --proyecto corrida2
AYUDA
}

# Opciones de línea de comandos. Las sobreescrituras se aplican solo a esta corrida,
# parametros.sh no se toca. Capturamos los overrides antes de abrir el log porque
# --proyecto cambia la carpeta de logs (DIR_LOGS).
PROYECTO_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) mostrar_ayuda; exit 0 ;;
        -p|--proyecto)
            shift; [ $# -gt 0 ] || { log_error "--proyecto necesita un valor (el nombre del proyecto)"; exit 1; }
            PROYECTO_OVERRIDE="$1" ;;
        --proyecto=*)
            PROYECTO_OVERRIDE="${1#*=}" ;;
        *) log_error "Argumento desconocido: '$1' (usa --proyecto o --help)"; exit 1 ;;
    esac
    shift
done

# Aplicamos el override sobre lo que trajo parametros.sh. El de --proyecto recalcula
# la carpeta de logs igual que parametros.sh (este script solo usa DIR_LOGS), para que
# el registro de esta corrida quede bajo el proyecto indicado.
if [ -n "$PROYECTO_OVERRIDE" ]; then
    PROYECTO="$PROYECTO_OVERRIDE"
    DIR_LOGS="logs/$PROYECTO"
fi

iniciar_registro "02_verificar_entorno"

# Para que el script pueda capturar todos los errores, no activamos el trap de errores, ya que se deben de reportar todos los errores al final. Lo que falte queda como ERROR en el archivo .err.

seleccionar_entorno    # definimos MOTOR y CONFIG_RECURSOS
seleccionar_marcador   # definimos CONFIG_MARCADOR

cabecera_registro "VERIFICACIÓN DEL ENTORNO."

# Activamos el entorno lanzador si existe (para ver que Java y Nextflow sean correctos)
if command -v conda >/dev/null 2>&1; then
    log_info "conda: $(conda --version)"
    source "$(dirname "$(dirname "${CONDA_EXE:-$(command -v conda)}")")/etc/profile.d/conda.sh"
    if conda env list | awk '{print $1}' | grep -qx "$ENV_LANZADOR"; then
        log_info "Entorno conda '$ENV_LANZADOR' existe"
        conda activate "$ENV_LANZADOR" 2>/dev/null
    else
        log_error "Entorno conda '$ENV_LANZADOR' no existe. Corre scripts/00_instalar_dependencias.sh"
    fi
else
    log_error "conda no está instalado"
fi

log_info "--------------------------------------------------------------------------"
log_info "Herramientas:"

# Java (debe ser >= 17)
if command -v java >/dev/null 2>&1; then
    JV="$(java -version 2>&1 | head -1)"
    JMAJOR="$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)"
    if [ "${JMAJOR:-0}" -ge 17 ] 2>/dev/null; then
        log_info "Java: $JV"
    else
        log_warn "Java demasiado viejo: $JV  (se necesita >= 17)"
    fi
else
    log_error "Java no disponible"
fi

# Nextflow
if command -v nextflow >/dev/null 2>&1; then
    log_info "Nextflow: $(nextflow -version 2>&1 | grep -i version | head -1 | tr -s ' ')"
else
    log_error "Nextflow no disponible  → corre scripts/00_instalar_dependencias.sh"
fi

# SLURM (solo en HPC): Nextflow necesita 'sbatch' en el job maestro para mandar las tareas
if [ "$ENTORNO" = "hpc" ]; then
    if command -v sbatch >/dev/null 2>&1; then
        log_info "SLURM: sbatch disponible"
    else
        log_error "sbatch no disponible. Verifica el entorno desde un nodo del clúster (p. ej. nodo5)"
    fi
fi

# Motor de contenedores. En el HPC, el job maestro (nodo5/27/28) solo orquesta y el motor
# corre en los nodos de cómputo (nodo27, nodo28), así que no se pide aquí.
case "$MOTOR" in
    docker)
        if [ "$ENTORNO" = "hpc" ]; then
            log_info "Motor: Docker en los nodos de cómputo (nodo27, nodo28). El job maestro no necesita Docker."
        elif docker info >/dev/null 2>&1; then
            log_info "Docker responde: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
        else
            log_error "MOTOR=docker pero el engine no responde (abre Docker Desktop y activa la integración WSL)"
        fi
        ;;
    singularity|apptainer)
        if command -v apptainer >/dev/null 2>&1; then
            log_info "Apptainer: $(apptainer --version 2>&1)"
        elif command -v singularity >/dev/null 2>&1; then
            log_info "Singularity: $(singularity --version 2>&1)"
        elif [ "$ENTORNO" = "hpc" ]; then
            log_warn "Singularity/Apptainer no disponible en el job maestro. El script 00 intenta"
            log_warn "  instalarlo por conda. Si no quedó, cárgalo con un módulo (p. ej. module load apptainer)."
        else
            log_error "Apptainer/Singularity no disponible (MOTOR=$MOTOR)  → corre scripts/00_instalar_dependencias.sh"
        fi
        ;;
    conda)
        log_info "Motor = conda (Nextflow crea un entorno por herramienta)"
        ;;
    *)
        log_error "MOTOR no válido: '$MOTOR' (usa docker, singularity, apptainer o conda)"
        ;;
esac

# Archivo de recursos del entorno elegido
if [ -f "$CONFIG_RECURSOS" ]; then
    log_info "Recursos: $CONFIG_RECURSOS"
else
    log_error "No existe el archivo de recursos: $CONFIG_RECURSOS"
fi

# Archivo de parámetros del marcador elegido
if [ -f "$CONFIG_MARCADOR" ]; then
    log_info "Parámetros: $CONFIG_MARCADOR"
else
    log_error "No existe el archivo de parámetros: $CONFIG_MARCADOR"
fi

# Pipeline en caché
if [ -d "$HOME/.nextflow/assets/nf-core/ampliseq" ]; then
    log_info "Pipeline nf-core/ampliseq en caché local"
else
    log_warn "El pipeline no está descargado. Se bajará en la primera ejecución."
fi

log_info "--------------------------------------------------------------------------"
log_info "Datos y configuración:"

# Carpeta de FASTQ
if [ -d "$CARPETA_FASTQ" ]; then
    N_FASTQ=$(find "$CARPETA_FASTQ" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null | wc -l)
    if [ "$N_FASTQ" -gt 0 ]; then
        log_info "FASTQ encontrados en $CARPETA_FASTQ: $N_FASTQ archivo(s)"
    else
        log_warn "Carpeta $CARPETA_FASTQ existe pero no tiene archivos .fastq.gz"
    fi
else
    log_error "Carpeta de FASTQ no existe: $CARPETA_FASTQ"
fi

# Samplesheet
if [ "$USAR_SAMPLESHEET" = "si" ]; then
    if [ -f "$SAMPLESHEET" ]; then
        log_info "Hoja de muestras: $SAMPLESHEET ($(($(wc -l < "$SAMPLESHEET")-1)) muestra/s)"
    else
        log_warn "Hoja de muestras no creada. Corre scripts/01_generar_samplesheet.sh"
    fi
fi

# Metadatos
if [ -n "$METADATA" ]; then
    [ -f "$METADATA" ] && log_info "Metadatos: $METADATA" \
                       || log_warn "METADATA apunta a un archivo inexistente: $METADATA"
else
    log_warn "No se encontraron metadatos. Se omitirán los análisis de diversidad de QIIME2."
fi

log_info "--------------------------------------------------------------------------"
log_info "Resumen de parámetros del análisis:"
log_info "   Entorno de ejecución:    $ENTORNO"
log_info "   Motor de ejecución:      $MOTOR"
log_info "   Marcador:                $MARCADOR"
FW="$(leer_yaml FW_primer "$CONFIG_MARCADOR")"
RV="$(leer_yaml RV_primer "$CONFIG_MARCADOR")"
TAXONOMIA="$(leer_taxonomia "$CONFIG_MARCADOR")"
log_info "   Primers:                 FW=${FW:-?}${RV:+  RV=$RV}"
[ "$MARCADOR" = "its" ] && log_info "   Región ITS (--cut_its):  $(leer_yaml cut_its "$CONFIG_MARCADOR")"
log_info "   Base de datos taxonómica:  ${TAXONOMIA:-?}"
log_info "   Diseño de lecturas:      $DISENO_LECTURAS"
log_info "=========================================================================="

# El verificador corre sin 'set -e' a propósito: recorre TODO el entorno y reporta
# cada problema con log_error sin abortar en el primero. Ya con la lista completa,
# refleja el resultado en el código de salida (≠ 0 si hubo algún error).
if [ "${LOG_ERRORES:-0}" -gt 0 ]; then
    log_warn "Verificación terminada con $LOG_ERRORES problema(s). Revisa los [ERROR] de arriba y corrígelos."
    exit 1
fi
log_info "Verificación terminada: entorno listo, sin errores."
exit 0
