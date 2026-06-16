#!/usr/bin/env bash
# =============================================================================
#  precargar_imagenes_docker_hpc.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Precarga todas las imágenes de nf-core/ampliseq en el Docker LOCAL
#  de cada nodo de cómputo (NODOS_TAREAS_DOCKER, p. ej. nodo27 nodo28), usando docker pull. El almacén
#  de Docker es por nodo y la conectividad al registro es intermitente, así que
#  precargar una vez, con reintentos, evita que una tarea falle a mitad de corrida
#  por un pull lento.
#
#  Córrelo desde el nodo interactivo (puede hacer srun a los nodos de cómputo). El
#  motor debe ser docker. La lista de imágenes la saca 'nextflow inspect' del
#  pipeline ya cacheado. Ese paso, al correr aquí (con internet), también precarga
#  los plugins de Nextflow que el job maestro necesitará offline.
#
#  Uso (desde la raíz del repo):  bash scripts/precargar_imagenes_docker_hpc.sh
# =============================================================================
set -euo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"
source "scripts/lib/registro.sh"
source "scripts/lib/marcador.sh"
iniciar_registro "precargar_imagenes_docker_hpc"

# Entorno con nextflow
if command -v conda >/dev/null 2>&1; then
    source "$(dirname "$(dirname "${CONDA_EXE:-$(command -v conda)}")")/etc/profile.d/conda.sh"
    conda activate "$ENV_LANZADOR" 2>/dev/null || true
fi
command -v nextflow >/dev/null 2>&1 || { log_error "Nextflow no disponible. Corre antes: bash scripts/00_instalar_dependencias.sh"; exit 1; }
command -v srun     >/dev/null 2>&1 || { log_error "no encontré 'srun'. Corre esto desde un nodo del clúster."; exit 1; }

seleccionar_marcador   # fija CONFIG_MARCADOR según MARCADOR

read -ra NODOS <<< "${NODOS_TAREAS_DOCKER:-nodo27 nodo28}"

# Entrada para que 'nextflow inspect' pueda resolver el grafo (igual que el script 03)
if [ "$USAR_SAMPLESHEET" = "si" ] && [ -f "$SAMPLESHEET" ]; then
    ENTRADA=( --input "$SAMPLESHEET" )
elif [ -d "$CARPETA_FASTQ" ]; then
    ENTRADA=( --input_folder "$CARPETA_FASTQ" )
else
    log_error "no hay entrada para 'inspect': falta $SAMPLESHEET (corre el script 01) o la carpeta $CARPETA_FASTQ."
    exit 1
fi

# 1) Lista de imágenes con 'nextflow inspect' (resuelve el nombre exacto que usará la
#    corrida, con el registro quay.io ya aplicado). NXF_OFFLINE=false porque aquí hay
#    internet: de paso se cachean los plugins del pipeline para la corrida offline.
LISTA="$DIR_LOGS/imagenes_docker_${SELLO}.txt"
log_info "Obteniendo la lista de imágenes con 'nextflow inspect' (marcador: $MARCADOR)…"
NXF_OFFLINE=false nextflow inspect nf-core/ampliseq -r "$VERSION_PIPELINE" \
    -profile docker \
    -params-file "$CONFIG_MARCADOR" \
    "${ENTRADA[@]}" \
    --outdir "$DIR_PROYECTO/.cache/inspect" \
    2>/dev/null \
  | grep -oE '"container"[[:space:]]*:[[:space:]]*"[^"]+"' \
  | sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/' \
  | sort -u > "$LISTA" || true

N="$(grep -c . "$LISTA" 2>/dev/null)" || N=0
if [ "$N" -eq 0 ]; then
    log_error "No pude extraer imágenes con 'nextflow inspect' (lista vacía: $LISTA)."
    log_error "  Revisa a mano:  nextflow inspect nf-core/ampliseq -r $VERSION_PIPELINE -profile docker -params-file $CONFIG_MARCADOR ${ENTRADA[*]} --outdir /tmp/insp"
    exit 1
fi
log_info "$N imágenes a precargar. Lista en: $LISTA"

# 2) docker pull en cada nodo, con reintentos (la lista vive en $HOME, visible por srun)
for n in "${NODOS[@]}"; do
    log_info "=========================================================================="
    log_info "Precargando imágenes en $n …"
    srun -w "$n" -p "${PARTICION_SLURM:-cicese}" --account="${CUENTA_SLURM:-metagenomica}" bash -lc '
        ok=0; fail=0
        while IFS= read -r img; do
            [ -z "$img" ] && continue
            for i in 1 2 3 4 5; do
                if docker pull "$img" >/dev/null 2>&1; then ok=$((ok+1)); break; fi
                if [ "$i" -eq 5 ]; then echo "  FALLO tras 5 intentos: $img"; fail=$((fail+1)); else sleep 10; fi
            done
        done < "'"$LISTA"'"
        echo "[$(hostname)] precargadas=$ok  fallidas=$fail"
    ' || log_warn "srun en $n terminó con error; revisa el log."
done

log_info "=========================================================================="
log_info "Listo. Si alguna quedó 'fallida', vuelve a correr este script: las ya"
log_info "descargadas se saltan al instante (docker pull es idempotente)."
log_info "Luego lanza el maestro con: bash scripts/lanzar_hpc.sh"
log_info "=========================================================================="
