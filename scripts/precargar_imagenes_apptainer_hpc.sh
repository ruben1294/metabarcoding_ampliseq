#!/usr/bin/env bash
# =============================================================================
#  precargar_imagenes_apptainer_hpc.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Precarga en referencias/ todo lo que el motor apptainer o singularity necesita para correr
#  offline: las imágenes de contenedor (.sif) en referencias/imagenes y las bases taxonómicas
#  del marcador en referencias/bases (ver DIR_REFERENCIAS en parametros.sh).
#
#  Córrelo UNA vez en el nodo interactivo (normalmente el único con salida a internet). Las imágenes las
#  baja 'nf-core (pipelines) download' (modo 'amend'). Las bases las baja con wget desde las mismas URL
#  que usa el pipeline, con su nombre original, para que la corrida offline las reutilice
#  (storeDir de ampliseq). Luego el script 03 corre offline leyendo de referencias/.
#
#  Uso (desde la raíz del repo):  bash scripts/precargar_imagenes_apptainer_hpc.sh
# =============================================================================
set -euo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"
source "scripts/lib/registro.sh"
source "scripts/lib/marcador.sh"
iniciar_registro "precargar_imagenes_apptainer_hpc"

# Entorno con nextflow + nf-core
if command -v conda >/dev/null 2>&1; then
    source "$(dirname "$(dirname "${CONDA_EXE:-$(command -v conda)}")")/etc/profile.d/conda.sh"
    conda activate "$ENV_LANZADOR" 2>/dev/null || true
fi

# nf-core tools hace la descarga y apptainer/singularity construye los archivos .sif
command -v nf-core >/dev/null 2>&1 \
    || { log_error "no encontré 'nf-core'. Instálalo en el nodo interactivo: pip install nf-core"; exit 1; }

# nf-core 3.0 (oct 2024) movió los comandos de pipeline bajo 'nf-core pipelines'. Las versiones
# nuevas (4.x) usan 'nf-core pipelines download'; las viejas (<3.0) usan 'nf-core download'.
if nf-core pipelines download --help >/dev/null 2>&1; then
    NFCORE_DOWNLOAD=(nf-core pipelines download)
elif nf-core download --help >/dev/null 2>&1; then
    NFCORE_DOWNLOAD=(nf-core download)
else
    log_error "esta versión de nf-core no acepta ni 'nf-core pipelines download' ni 'nf-core download' (revisa: nf-core --version)"
    exit 1
fi
command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 \
    || { log_error "no encontré Apptainer ni Singularity aquí, hace falta uno para construir los .sif."; exit 1; }

DIR_REFERENCIAS="${DIR_REFERENCIAS:-$DIR_PROYECTO/referencias}"
CACHE="$DIR_REFERENCIAS/imagenes"
BASES="$DIR_REFERENCIAS/bases"
mkdir -p "$CACHE" "$BASES" || { log_error "no puedo crear referencias en $DIR_REFERENCIAS (¿permiso de escritura?)"; exit 1; }
export NXF_SINGULARITY_CACHEDIR="$CACHE"
export NXF_APPTAINER_CACHEDIR="$CACHE"

log_info "Descargando imágenes de nf-core/ampliseq r${VERSION_PIPELINE} a: $CACHE"
log_info "(este proceso puede ser tardado)"

# 'amend' deja las imágenes en NXF_SINGULARITY_CACHEDIR (no las copia a otra carpeta).
# El pipeline en sí se descarga a una carpeta temporal que luego borramos: para correr
# ya usamos la copia de 'nextflow pull' (script 00). Forzamos NXF_OFFLINE=false por si
# el clúster lo trae activado. Si tu versión de nf-core usa otros nombres de flag,
# ajústalos (nf-core download --help); lo esencial es --container-system singularity
# y que NXF_SINGULARITY_CACHEDIR apunte a la caché compartida.
TMP_DL="$(mktemp -d)"
trap 'rm -rf "$TMP_DL"' EXIT
NXF_OFFLINE=false "${NFCORE_DOWNLOAD[@]}" ampliseq \
    --revision "$VERSION_PIPELINE" \
    --container-system singularity \
    --container-cache-utilisation amend \
    --compress none \
    --outdir "$TMP_DL/ampliseq_dl"

# --- Bases de datos del marcador ---
# En un HPC sin internet en los nodos, también hay que bajar las bases aquí.
# El pipeline guarda cada base por su nombre de archivo (storeDir), así que si
# dejamos el archivo crudo con su nombre original en referencias/bases, la corrida offline lo
# reutiliza sin volver a bajarlo. Derivamos las URL del marcador activo desde la config del
# propio pipeline, las mismas que usaría la corrida.
seleccionar_marcador   # fija MARCADOR y CONFIG_MARCADOR
CFG_DB="${NXF_HOME:-$HOME/.nextflow}/assets/nf-core/ampliseq/conf/ref_databases.config"
TAX_DADA="$(leer_yaml dada_ref_taxonomy "$CONFIG_MARCADOR")"
TAX_QIIME="$(leer_yaml qiime_ref_taxonomy "$CONFIG_MARCADOR")"

if [ -z "$TAX_DADA" ] && [ -z "$TAX_QIIME" ]; then
    log_warn "El marcador no define dada_ref_taxonomy ni qiime_ref_taxonomy, no precargo bases."
elif [ ! -f "$CFG_DB" ]; then
    log_warn "No encuentro ref_databases.config en $CFG_DB."
    log_warn "  Precarga el pipeline antes (script 00) o baja las bases a mano a: $BASES"
else
    if [ -n "$TAX_DADA" ]; then
        SECCION="dada_ref_databases"; LLAVE="$TAX_DADA"
    else
        SECCION="qiime_ref_databases"; LLAVE="$TAX_QIIME"
    fi
    log_info "Precargando bases del marcador $MARCADOR ($LLAVE) en: $BASES"
    # Sacamos las URL de la entrada 'LLAVE' dentro de su sección (DADA2 o QIIME2). Cotejamos la
    # llave de forma literal porque lleva '=' y puntos de versión, que confundirían a una regex.
    URLS="$(awk -v sec="$SECCION" -v key="$LLAVE" '
        $0 ~ ("^    " sec " \\{")                { ensec=1; next }
        ensec && /^    [a-z0-9_]+ \{/            { ensec=0 }
        ensec && index($0, "\047" key "\047 {")  { enent=1 }
        enent && /file *= *\[/ { n=split($0, p, "\""); for (i=2; i<=n; i+=2) print p[i]; exit }
        enent && /^        \}/ { enent=0 }
    ' "$CFG_DB")"
    if [ -z "$URLS" ]; then
        log_warn "No pude derivar las URL de '$LLAVE' en $SECCION. Baja las bases a mano a: $BASES"
    else
        while IFS= read -r u; do
            [ -z "$u" ] && continue
            destino="$BASES/$(basename "$u")"
            if [ -s "$destino" ]; then
                log_info "  ya está: $(basename "$u")"
            else
                log_info "  bajando: $u"
                wget -q -O "$destino" "$u" \
                    || { rm -f "$destino"; log_warn "  no pude bajar $u (sigo con las demás)"; }
            fi
        done <<< "$URLS"
    fi
fi

log_info "--------------------------------------------------------------------------"
log_info "Listo."
log_info "Imágenes en: $CACHE"
log_info "Bases en:    $BASES"
ls -lh "$CACHE" "$BASES" 2>/dev/null | head -n 30
log_info "Ahora puedes correr el maestro con MOTOR=apptainer o singularity."
log_info "--------------------------------------------------------------------------"
