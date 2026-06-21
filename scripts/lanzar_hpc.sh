#!/usr/bin/env bash
# =============================================================================
#  lanzar_hpc.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Envía el job maestro al HPC eligiendo un nodo disponible de los permitidos
#  (NODOS_MAESTRO en parametros.sh: nodo5, nodo27 o nodo28). El job maestro es el orquestador y pide pocos recursos
#  (2 CPU, 4 GB), y puede compartir nodo27/nodo28 con las tareas hijas. Prefiere el
#  primero de la lista con CPUs libres. Si todos están llenos, elige el de más CPUs
#  libres y manda ahí al job maestro. El --nodelist que pasa aquí sobrescribe el de lanzar_hpc.slurm.
#
#  Uso (desde la raíz del repo):  bash scripts/lanzar_hpc.sh
# =============================================================================
set -euo pipefail

# Nos situamos en la raíz del repo y cargamos la configuración
DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"

# Nodos permitidos para el job maestro (orden de preferencia), cuenta y partición de SLURM
# (vienen de parametros.sh, el valor después de ':-' es el respaldo de OMICA).
read -ra NODOS <<< "${NODOS_MAESTRO:-nodo5 nodo27 nodo28}"
CUENTA="${CUENTA_SLURM:-metagenomica}"
PARTICION="${PARTICION_SLURM:-cicese}"

command -v sbatch >/dev/null 2>&1 \
    || { echo "[lanzador] no encontré 'sbatch'. Lanza desde un nodo del clúster." >&2; exit 1; }

# Estado del nodo en la partición (idle, mix, alloc, drain…). Vacío si no aparece.
estado_nodo() { sinfo -h -p "$PARTICION" -n "$1" -o "%t" 2>/dev/null | head -1; }
# CPUs libres del nodo (campo 'I' de A/I/O/T). Vacío si no aparece.
cpus_libres() { sinfo -h -p "$PARTICION" -n "$1" -o "%C" 2>/dev/null | head -1 | cut -d/ -f2; }

# 1) Primer nodo con espacio (idle o mix)
elegido=""
for nodo in "${NODOS[@]}"; do
    estado="$(estado_nodo "$nodo")"
    echo "[lanzador] $nodo: estado '${estado:-desconocido}'"
    if [ "$estado" = "idle" ] || [ "$estado" = "mix" ]; then
        elegido="$nodo"
        break
    fi
done

# 2) Si ninguno tiene espacio, el de más CPUs libres (el job maestro se calendarizará allí)
if [ -z "$elegido" ]; then
    mejor=-1
    for nodo in "${NODOS[@]}"; do
        libres="$(cpus_libres "$nodo")"; libres="${libres:-0}"
        if [ "$libres" -gt "$mejor" ]; then mejor="$libres"; elegido="$nodo"; fi
    done
    echo "[lanzador] todos ocupados, el job maestro se calendarizará en $elegido (CPUs libres: $mejor)."
fi

echo "[lanzador] enviando el job maestro a $elegido (cuenta: $CUENTA, partición: $PARTICION)…"
# --account/--partition/--nodelist en la CLI de sbatch sobrescriben las directivas
# #SBATCH estáticas de lanzar_hpc.slurm, así que la cuenta sale de parametros.sh.
sbatch --account="$CUENTA" --partition="$PARTICION" --nodelist="$elegido" "$@" scripts/lanzar_hpc.slurm
