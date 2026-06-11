#!/usr/bin/env bash
# =============================================================================
#  00_instalar_dependencias.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Prepara lo necesario para correr nf-core/ampliseq: Java 17 y Nextflow, en un
#  entorno conda aislado (ENV_LANZADOR). El motor predeterminado es Docker, que no
#  se instala aquí (en local lo da Docker Desktop; en HPC vive en los nodos de
#  cómputo). Es idempotente: puedes correrlo varias veces sin problema.
#
#  Uso:   bash scripts/00_instalar_dependencias.sh
# =============================================================================
set -euo pipefail

# Nos ubicamos en la raíz del proyecto y cargamos la configuración
DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"

source "scripts/lib/registro.sh"
source "scripts/lib/entorno.sh"
iniciar_registro "00_instalar_dependencias"

# Local o HPC: lo pregunta si ENTORNO está vacío y fija MOTOR y CONFIG_RECURSOS
seleccionar_entorno
activar_trap_errores

# Validamos el motor ya resuelto
case "$MOTOR" in
    docker|singularity|apptainer|conda) : ;;
    *) log_error "MOTOR no válido: '$MOTOR' (usa docker, singularity, apptainer o conda)"; exit 1 ;;
esac

# El entorno lanzador siempre lleva Java + Nextflow. Con el motor predeterminado
# (Docker) no hace falta más: en local lo da Docker Desktop y en HPC corre en los
# nodos de cómputo. Solo instalamos Apptainer por conda si lo fuerzas como motor,
# no está en el PATH y corres en local.
INSTALAR_APPTAINER="no"
if [ "$MOTOR" = "singularity" ] || [ "$MOTOR" = "apptainer" ]; then
    if command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1; then
        :
    elif [ "$ENTORNO" = "local" ]; then
        INSTALAR_APPTAINER="si"
    fi
fi

cabecera_registro "INSTALACIÓN DE DEPENDENCIAS. Proyecto: $PROYECTO"
log_info "Carpeta del proyecto: $DIR_PROYECTO"
log_info "Entorno conda:        $ENV_LANZADOR"

# 1) Comprobamos que conda existe
if ! command -v conda >/dev/null 2>&1; then
    log_error "No se encontró 'conda'. Instala Miniforge primero:"
    log_error "  https://github.com/conda-forge/miniforge"
    exit 1
fi
# Hacemos que 'conda activate' funcione dentro de este script (shell no interactivo)
source "$(conda info --base)/etc/profile.d/conda.sh"
log_info "conda detectado: $(conda --version)"

# 2) Configuramos los canales y el solucionador (solver)
# Orden recomendado por bioconda. 'strict' evita mezclas raras.
conda config --add channels defaults    >/dev/null 2>&1 || true
conda config --add channels bioconda     >/dev/null 2>&1 || true
conda config --add channels conda-forge  >/dev/null 2>&1 || true
conda config --set channel_priority strict >/dev/null 2>&1 || true
log_info "Canales conda configurados (conda-forge > bioconda > defaults)."

# 3) Definimos los paquetes del entorno lanzador
PAQUETES=( "openjdk=17" )
if [ -n "${VERSION_NEXTFLOW:-}" ]; then
    PAQUETES+=( "nextflow=${VERSION_NEXTFLOW}" )
else
    PAQUETES+=( "nextflow" )
fi
[ "$INSTALAR_APPTAINER" = "si" ] && PAQUETES+=( "apptainer" )
log_info "Paquetes a instalar: ${PAQUETES[*]}"

# Paquetes de respaldo (sin versión fija) por si falla anclar la versión exacta.
PAQUETES_FLEX=( "openjdk=17" "nextflow" )
[ "$INSTALAR_APPTAINER" = "si" ] && PAQUETES_FLEX+=( "apptainer" )

# 4) Crear o actualizar el entorno
if conda env list | awk '{print $1}' | grep -qx "$ENV_LANZADOR"; then
    log_info "El entorno '$ENV_LANZADOR' ya existe, actualizando…"
    conda install -n "$ENV_LANZADOR" -y "${PAQUETES[@]}" \
      || { log_warn "No se pudo anclar la versión, reintentando flexible…"
           conda install -n "$ENV_LANZADOR" -y "${PAQUETES_FLEX[@]}"; }
else
    log_info "Creando el entorno '$ENV_LANZADOR'…"
    conda create -n "$ENV_LANZADOR" -y "${PAQUETES[@]}" \
      || { log_warn "No se pudo anclar la versión, reintentando flexible…"
           conda create -n "$ENV_LANZADOR" -y "${PAQUETES_FLEX[@]}"; }
fi

# Sin versión fija, forzamos la más reciente (conda install no siempre sube la ya instalada).
if [ -z "${VERSION_NEXTFLOW:-}" ]; then
    log_info "Sin versión fija: actualizando Nextflow a la más reciente disponible…"
    conda update -n "$ENV_LANZADOR" -y nextflow \
      || log_warn "No pude actualizar Nextflow; se queda la versión instalada."
fi

conda activate "$ENV_LANZADOR"
log_info "Entorno '$ENV_LANZADOR' activo."

# 5) nf-core tools (opcional, no es indispensable para ejecutar el flujo)
if ! command -v nf-core >/dev/null 2>&1; then
    log_info "Instalando nf-core tools…"
    conda install -n "$ENV_LANZADOR" -y nf-core \
      || pip install --quiet nf-core \
      || log_warn "No se pudo instalar nf-core tools, pero el flujo igual funciona."
fi

# 5b) Verificamos el motor de contenedores elegido
case "$MOTOR" in
    docker)
        if [ "$ENTORNO" = "hpc" ]; then
            log_info "Motor Docker: corre en los nodos de cómputo (nodo27, nodo28); el maestro (nodo5) no lo necesita."
        elif docker info >/dev/null 2>&1; then
            log_info "Docker responde: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
        else
            log_warn "MOTOR=docker pero el engine no responde. Abre Docker Desktop y activa"
            log_warn "  la integración con esta distro: Settings → Resources → WSL integration."
        fi
        ;;
    singularity|apptainer)
        if command -v apptainer >/dev/null 2>&1; then
            log_info "Apptainer disponible: $(apptainer --version 2>&1)"
        elif command -v singularity >/dev/null 2>&1; then
            log_info "Singularity disponible: $(singularity --version 2>&1)"
        elif [ "$ENTORNO" = "hpc" ]; then
            log_warn "No encontré Singularity/Apptainer. En el clúster suele cargarse con un"
            log_warn "  módulo (p. ej. module load apptainer); cárgalo y revisa con el script 02."
        else
            log_warn "No se encontró 'apptainer' a pesar de haber intentado instalarlo."
        fi
        ;;
    conda)
        log_info "Motor conda: Nextflow creará un entorno por herramienta al ejecutar."
        ;;
esac

# 6) Variables de caché en el disco grande (evita llenar el disco del SO)
export NXF_SINGULARITY_CACHEDIR="$DIR_PROYECTO/.cache/singularity"
export NXF_CONDA_CACHEDIR="$DIR_PROYECTO/.cache/conda"
mkdir -p "$NXF_SINGULARITY_CACHEDIR" "$NXF_CONDA_CACHEDIR"

# 7) Precargamos el pipeline (queda en caché por si se quiere correr offline)
log_info "Descargando nf-core/ampliseq r${VERSION_PIPELINE} a la caché local…"
nextflow pull nf-core/ampliseq -r "${VERSION_PIPELINE}" \
  || log_warn "No se pudo precargar el pipeline, se descargará en la primera ejecución."

# 8) Verificamos e imprimimos versiones
log_info "--------------------------------------------------------------------------"
log_info "Versiones instaladas:"
log_info "   Java     : $(java -version 2>&1 | head -1)"
log_info "   Nextflow : $(nextflow -version 2>&1 | grep -i version | head -1 | tr -s ' ')"
case "$MOTOR" in
    docker)
        if [ "$ENTORNO" = "hpc" ]; then log_info "   Docker   : en nodos de cómputo (nodo27, nodo28)"
        else                            log_info "   Docker   : $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'no responde')"; fi ;;
    singularity|apptainer) log_info "   Apptainer: $(apptainer --version 2>&1 || echo 'no disponible')" ;;
    conda)                 log_info "   Motor    : conda (entornos por herramienta)" ;;
esac
command -v nf-core >/dev/null 2>&1 && log_info "   nf-core  : $(nf-core --version 2>&1 | head -1)"
log_info "--------------------------------------------------------------------------"

# 9) Guardamos un registro de versiones
mkdir -p registros
{
    echo "# Registro de instalación: $(date -Is)"
    echo "Proyecto:        $PROYECTO"
    echo "Entorno:         $ENTORNO"
    echo "Motor:           $MOTOR"
    echo "Entorno conda:   $ENV_LANZADOR"
    echo "Pipeline:        nf-core/ampliseq r${VERSION_PIPELINE}"
    echo "conda:           $(conda --version)"
    echo "Java:            $(java -version 2>&1 | head -1)"
    echo "Nextflow:        $(nextflow -version 2>&1 | grep -i version | head -1 | tr -s ' ')"
    case "$MOTOR" in
        docker)
            if [ "$ENTORNO" = "hpc" ]; then echo "Docker:          en nodos de cómputo (nodo27, nodo28)"
            else                            echo "Docker:          $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo n/d)"; fi ;;
        singularity|apptainer) echo "Apptainer:       $(apptainer --version 2>&1 || echo n/d)" ;;
    esac
    command -v nf-core >/dev/null 2>&1 && echo "nf-core tools:   $(nf-core --version 2>&1 | head -1)"
} > "registros/versiones_setup.txt"
log_info "Registro de versiones guardado en registros/versiones_setup.txt"

log_info "=========================================================================="
log_info "¡Listo! Dependencias instaladas."
log_info "Siguiente paso:"
log_info "   1) Copia tus archivos FASTQ en:  $CARPETA_FASTQ/"
log_info "   2) Genera la hoja de muestras:  bash scripts/01_generar_samplesheet.sh"
log_info "   3) Ejecuta el análisis:         bash scripts/03_ejecutar_ampliseq.sh"
log_info "=========================================================================="
