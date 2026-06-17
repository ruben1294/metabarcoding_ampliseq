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
#         bash scripts/00_instalar_dependencias.sh --entorno hpc   (sobreescribe parametros.sh)
#         bash scripts/00_instalar_dependencias.sh --proyecto corrida2  (sobreescribe parametros.sh)
#         bash scripts/00_instalar_dependencias.sh --help      (muestra la ayuda)
# =============================================================================
set -euo pipefail

# Nos ubicamos en la raíz del proyecto y cargamos la configuración
DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"

source "scripts/lib/registro.sh"
source "scripts/lib/entorno.sh"

# Ayuda de la línea de comandos
mostrar_ayuda() {
    cat <<'AYUDA'
Uso: bash scripts/00_instalar_dependencias.sh [opciones]

Prepara el entorno conda con Java y Nextflow según configuracion/parametros.sh.
Las opciones de abajo sobreescriben, solo para esta corrida, lo definido en parametros.sh.

Opciones:
  -e, --entorno  <local|hpc>   Dónde se correrá el pipeline. Sobreescribe ENTORNO de
                               parametros.sh (afina los mensajes del motor; p. ej. la
                               sugerencia de 'module load apptainer' en HPC).
  -p, --proyecto <nombre>      Nombre del proyecto. Sobreescribe PROYECTO de
                               parametros.sh (y con él la carpeta de logs).
  -h, --help                   Muestra esta ayuda y termina.

Ejemplos:
  bash scripts/00_instalar_dependencias.sh
  bash scripts/00_instalar_dependencias.sh --entorno hpc --proyecto corrida2
AYUDA
}

# Opciones de línea de comandos. Las sobreescrituras se aplican solo a esta corrida;
# parametros.sh no se toca. Capturamos los overrides antes de abrir el log porque
# --proyecto cambia la carpeta de logs (DIR_LOGS).
PROYECTO_OVERRIDE=""; ENTORNO_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) mostrar_ayuda; exit 0 ;;
        -e|--entorno)
            shift; [ $# -gt 0 ] || { log_error "--entorno necesita un valor (local o hpc)"; exit 1; }
            ENTORNO_OVERRIDE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" ;;
        --entorno=*)
            ENTORNO_OVERRIDE="$(printf '%s' "${1#*=}" | tr '[:upper:]' '[:lower:]')" ;;
        -p|--proyecto)
            shift; [ $# -gt 0 ] || { log_error "--proyecto necesita un valor (el nombre del proyecto)"; exit 1; }
            PROYECTO_OVERRIDE="$1" ;;
        --proyecto=*)
            PROYECTO_OVERRIDE="${1#*=}" ;;
        *) log_error "Argumento desconocido: '$1' (usa --entorno, --proyecto o --help)"; exit 1 ;;
    esac
    shift
done

# Aplicamos los overrides sobre lo que trajo parametros.sh. El de --proyecto recalcula
# la carpeta de logs igual que parametros.sh (este script solo usa DIR_LOGS), para que
# el registro de versiones de esta corrida quede bajo el proyecto indicado.
[ -n "$ENTORNO_OVERRIDE" ] && ENTORNO="$ENTORNO_OVERRIDE"
if [ -n "$PROYECTO_OVERRIDE" ]; then
    PROYECTO="$PROYECTO_OVERRIDE"
    DIR_LOGS="logs/$PROYECTO"
fi

iniciar_registro "00_instalar_dependencias"

# Local o HPC: lo pregunta si ENTORNO está vacío y fija MOTOR y CONFIG_RECURSOS
seleccionar_entorno
activar_trap_errores

# Validamos el motor ya resuelto
case "$MOTOR" in
    docker|singularity|apptainer|conda) : ;;
    *) log_error "MOTOR no válido: '$MOTOR' (usa docker, singularity, apptainer o conda)"; exit 1 ;;
esac

# El entorno lanzador siempre lleva Java y Nextflow. Con el motor predeterminado
# (Docker) no hace falta más: en local lo da Docker Desktop y en HPC corre en los
# nodos de cómputo. Si fuerzas Apptainer/Singularity como motor y no está en el PATH,
# intentamos instalarlo por conda en un paso aparte best-effort (ver punto 4b), tanto en
# local como en HPC. En HPC casi siempre conviene el del módulo (module load apptainer),
# pero igual probamos y, si falla, lo avisamos sin abortar.
INSTALAR_APPTAINER="no"
if [ "$MOTOR" = "singularity" ] || [ "$MOTOR" = "apptainer" ]; then
    if command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1; then
        :
    else
        INSTALAR_APPTAINER="si"
    fi
fi

cabecera_registro "INSTALACIÓN DE DEPENDENCIAS."
log_info "Carpeta del proyecto: $DIR_PROYECTO"
log_info "Entorno conda:        $ENV_LANZADOR"

# 1) Comprobamos que conda existe
if ! command -v conda >/dev/null 2>&1; then
    log_error "No se encontró 'conda'. Instala Miniforge primero:"
    log_error "  https://github.com/conda-forge/miniforge"
    exit 1
fi
# Hacemos que 'conda activate' funcione dentro de este script (shell no interactivo).
# Derivamos la base del binario de conda (CONDA_EXE o el PATH) en vez de 'conda info
# --base': si conda trae un plugin ruidoso (p. ej. anaconda-anon-usage) que escribe en
# stdout, contaminaría la sustitución y la ruta quedaría rota.
source "$(dirname "$(dirname "${CONDA_EXE:-$(command -v conda)}")")/etc/profile.d/conda.sh"
log_info "conda detectado: $(conda --version)"

# 2) Configuramos los canales y el solucionador (solver)
# Orden recomendado por bioconda. 'strict' evita mezclas raras.
conda config --add channels defaults    >/dev/null 2>&1 || true
conda config --add channels bioconda     >/dev/null 2>&1 || true
conda config --add channels conda-forge  >/dev/null 2>&1 || true
conda config --set channel_priority strict >/dev/null 2>&1 || true
log_info "Canales conda configurados (conda-forge > bioconda > defaults)."

# 3) Definimos los paquetes del entorno lanzador. Apptainer NO va aquí: lo instalamos
# aparte y best-effort (punto 4b) para que un fallo suyo no arrastre a Java/Nextflow.
PAQUETES=( "openjdk=17" )
if [ -n "${VERSION_NEXTFLOW:-}" ]; then
    PAQUETES+=( "nextflow=${VERSION_NEXTFLOW}" )
else
    PAQUETES+=( "nextflow" )
fi
log_info "Paquetes a instalar: ${PAQUETES[*]}"

# Paquetes de respaldo (sin versión fija) por si falla usar la versión exacta.
PAQUETES_FLEX=( "openjdk=17" "nextflow" )

# Apagamos nounset durante las operaciones de conda: install/update/create activan de
# paso el entorno base, cuyos scripts de activación (p. ej. qt-main_activate.sh) leen
# variables sin definir y con 'set -u' eso abortaría el script. Lo reactivamos al final.
set +u

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
    log_info "Sin versión fija, actualizando Nextflow a la más reciente disponible…"
    conda update -n "$ENV_LANZADOR" -y nextflow \
      || log_warn "No pude actualizar Nextflow, se queda la versión instalada."
fi

conda activate "$ENV_LANZADOR"
log_info "Entorno '$ENV_LANZADOR' activo."

# 4b) Apptainer como paso aparte y best-effort. Lo separamos del install crítico para que
# un fallo (típico en HPC, donde el apptainer de conda-forge no siempre funciona sin
# setuid/namespaces) no aborte el script ni arrastre a Java/Nextflow. Si falla, lo avisamos
# y seguimos. El detalle y la sugerencia de 'module load' los da el punto 5b.
if [ "$INSTALAR_APPTAINER" = "si" ]; then
    log_info "Apptainer no está en el PATH. Intento instalarlo por conda…"
    if conda install -n "$ENV_LANZADOR" -y apptainer; then
        log_info "Apptainer instalado por conda."
    else
        log_warn "No se pudo instalar Apptainer por conda. Continúo sin abortar (ver punto 5b)."
    fi
fi

# 5) nf-core tools (opcional, no es indispensable para ejecutar el flujo)
# El solver clásico de conda se atora resolviendo el árbol de nf-core, forzamos
# libmamba (rápido) y, con timeout, evitamos que se quede atorado. Si falla, usamos pip.
if ! command -v nf-core >/dev/null 2>&1; then
    log_info "Instalando nf-core tools…"
    timeout 600 conda install -n "$ENV_LANZADOR" -y --solver=libmamba nf-core \
      || pip install --quiet nf-core \
      || log_warn "No se pudo instalar nf-core tools, pero el flujo igual funciona."
fi

# Reactivamos nounset para el resto del script.
set -u

# 5b) Verificamos el motor de contenedores elegido
case "$MOTOR" in
    docker)
        if [ "$ENTORNO" = "hpc" ]; then
            log_info "Motor Docker: corre en los nodos de cómputo (nodo27, nodo28), el job maestro (nodo5) no lo necesita."
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

# 6) Variables de caché en el disco grande (evita llenar el disco del SO). Con apptainer o
# singularity las imágenes van en referencias/imagenes, la misma ruta que usan el script 03 y
# el precargado. En el resto, la caché del proyecto.
if [ "$MOTOR" = "apptainer" ] || [ "$MOTOR" = "singularity" ]; then
    export NXF_SINGULARITY_CACHEDIR="${DIR_REFERENCIAS:-$DIR_PROYECTO/referencias}/imagenes"
else
    export NXF_SINGULARITY_CACHEDIR="$DIR_PROYECTO/.cache/singularity"
fi
export NXF_APPTAINER_CACHEDIR="$NXF_SINGULARITY_CACHEDIR"
export NXF_CONDA_CACHEDIR="$DIR_PROYECTO/.cache/conda"
mkdir -p "$NXF_SINGULARITY_CACHEDIR" "$NXF_CONDA_CACHEDIR"

# 7) Precargamos el pipeline en la caché (~/.nextflow/assets). Imprescindible en HPC:
# los nodos de cómputo no tienen internet, así que el maestro corre offline y usa
# este precargado. Hazlo en el nodo interactivo (el único con salida a internet).
log_info "Descargando nf-core/ampliseq r${VERSION_PIPELINE} a la caché local…"
# Forzamos NXF_OFFLINE=false por si el clúster lo trae activado por defecto (eso
# bloquearía la descarga aunque aquí sí haya internet).
NXF_OFFLINE=false nextflow pull nf-core/ampliseq -r "${VERSION_PIPELINE}" \
  || log_warn "No se pudo precargar el pipeline. En local se baja en la primera corrida; en HPC el maestro fallará offline hasta que esto funcione (corre con internet)."

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
mkdir -p "$DIR_LOGS"
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
} > "$DIR_LOGS/versiones_setup.txt"
log_info "Registro de versiones guardado en $DIR_LOGS/versiones_setup.txt"

log_info "=========================================================================="
log_info "¡Listo! Dependencias instaladas."
log_info "Siguiente paso:"
log_info "   1) Copia tus archivos FASTQ en:  $CARPETA_FASTQ/"
log_info "   2) Genera la hoja de muestras:  bash scripts/01_generar_samplesheet.sh"
log_info "   3) Ejecuta el análisis:         bash scripts/03_ejecutar_ampliseq.sh"
log_info "=========================================================================="
