#!/usr/bin/env bash
# =============================================================================
#  precargar_imagenes_apptainer_hpc.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Precarga las imágenes de contenedor (.sif) de nf-core/ampliseq en la caché
#  compartida de LUSTRE (DIR_CACHE_SINGULARITY en parametros.sh), para correr con
#  motor apptainer/singularity en los nodos de cómputo, que no tienen internet.
#
#  Córrelo UNA vez en el nodo interactivo (el único con salida a internet). Usa
#  'nf-core download', que baja el pipeline y todas sus imágenes y las deja en la
#  caché (modo 'amend'). Luego el script 03 corre offline leyéndolas de ahí.
#
#  Uso (desde la raíz del repo):  bash scripts/precargar_imagenes_apptainer_hpc.sh
# =============================================================================
set -euo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"
source "scripts/lib/registro.sh"
iniciar_registro "precargar_imagenes_apptainer_hpc"

# Entorno con nextflow + nf-core
if command -v conda >/dev/null 2>&1; then
    source "$(dirname "$(dirname "${CONDA_EXE:-$(command -v conda)}")")/etc/profile.d/conda.sh"
    conda activate "$ENV_LANZADOR" 2>/dev/null || true
fi

# nf-core tools hace la descarga; apptainer/singularity construye los .sif
command -v nf-core >/dev/null 2>&1 \
    || { log_error "no encontré 'nf-core'. Instálalo en el nodo interactivo: pip install nf-core"; exit 1; }
command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 \
    || { log_error "no encontré apptainer ni singularity aquí; hace falta uno para construir los .sif."; exit 1; }

CACHE="${DIR_CACHE_SINGULARITY:-$DIR_PROYECTO/.cache/singularity}"
mkdir -p "$CACHE" || { log_error "no puedo crear la caché $CACHE (¿permiso de escritura en LUSTRE?)"; exit 1; }
export NXF_SINGULARITY_CACHEDIR="$CACHE"
export NXF_APPTAINER_CACHEDIR="$CACHE"

log_info "Descargando imágenes de nf-core/ampliseq r${VERSION_PIPELINE} a: $CACHE"
log_info "(esto tarda: son ~15-20 imágenes; déjalo correr)"

# 'amend' deja las imágenes en NXF_SINGULARITY_CACHEDIR (no las copia a otra carpeta).
# El pipeline en sí se descarga a una carpeta temporal que luego borramos: para correr
# ya usamos la copia de 'nextflow pull' (script 00). Forzamos NXF_OFFLINE=false por si
# el clúster lo trae activado. Si tu versión de nf-core usa otros nombres de flag,
# ajústalos (nf-core download --help); lo esencial es --container-system singularity
# y que NXF_SINGULARITY_CACHEDIR apunte a la caché compartida.
TMP_DL="$(mktemp -d)"
trap 'rm -rf "$TMP_DL"' EXIT
NXF_OFFLINE=false nf-core download ampliseq \
    --revision "$VERSION_PIPELINE" \
    --container-system singularity \
    --container-cache-utilisation amend \
    --compress none \
    --outdir "$TMP_DL/ampliseq_dl"

log_info "--------------------------------------------------------------------------"
log_info "Listo. Imágenes en: $CACHE"
log_info "Contenido (primeras líneas):"
ls -lh "$CACHE" 2>/dev/null | head -n 20
log_info "Ahora puedes correr el maestro con MOTOR=apptainer (o singularity)."
log_info "--------------------------------------------------------------------------"
