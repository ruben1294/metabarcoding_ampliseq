#!/usr/bin/env bash
#SBATCH --job-name=ampliseq_maestro
#SBATCH --account=metagenomica
#SBATCH --partition=cicese
# Nodo por defecto si lanzas este .slurm directo. scripts/lanzar_hpc.sh lo
# sobrescribe con el primer nodo permitido (NODOS_MAESTRO) que tenga hueco.
#SBATCH --nodelist=nodo5
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=72:00:00
# El log del maestro va a logs/ (no a logs/<PROYECTO>/): las directivas #SBATCH son
# estáticas y no expanden $PROYECTO. El log del análisis sí queda en logs/<PROYECTO>/.
#SBATCH --output=logs/ampliseq_maestro_%j.out
#SBATCH --error=logs/ampliseq_maestro_%j.err
# =============================================================================
#  lanzar_hpc.slurm
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Lanza el pipeline en el HPC de OMICA (CICESE). El job maestro es un orquestador
#  ligero (2 CPU, 4 GB) que corre en uno de nodo5/nodo27/nodo28; Nextflow manda cada
#  tarea a SLURM y esas tareas usan Docker en nodo27 y nodo28. Este maestro debe
#  mantenerse vivo durante todo el análisis.
#
#  Para elegir el nodo automáticamente usa el wrapper (recomendado):
#     bash scripts/lanzar_hpc.sh
#  Este .slurm directo manda el maestro a nodo5 (ver --nodelist abajo).
#
#  Antes de iniciarlo:
#    1) En configuracion/parametros.sh fija ENTORNO="hpc" y MARCADOR.
#    2) Corre una vez scripts/00_instalar_dependencias.sh (crea el entorno conda
#       con Nextflow + Java en el clúster).
#    3) Genera la hoja de muestras: scripts/01_generar_samplesheet.sh
#
#  Uso (desde la raíz del repo):
#     bash scripts/lanzar_hpc.sh        (elige el nodo automáticamente, recomendado)
#     sbatch scripts/lanzar_hpc.slurm   (directo, el maestro va a nodo5)
# =============================================================================
set -euo pipefail

# Nos situamos en la raíz del repo (la carpeta desde donde se hizo sbatch)
cd "${SLURM_SUBMIT_DIR:-$PWD}"

echo "[maestro] nodo: $(hostname)  job: ${SLURM_JOB_ID:-?}"
echo "[maestro] repo: $(pwd)"

# conda debe estar en el PATH para que el script 03 active el entorno lanzador.
# En OMICA viene como módulo; lo cargamos sin abortar si no existe (otros clústeres
# no lo tendrán). Ajusta el nombre del módulo a tu clúster, o quita esta línea si no
# usa 'module'. Si falla, el bloque de abajo busca conda en las rutas habituales.
module load conda-2023_metagenomica 2>/dev/null || true
if ! command -v conda >/dev/null 2>&1; then
    for base in "$HOME/miniforge3" "$HOME/miniconda3" "$HOME/anaconda3"; do
        if [ -f "$base/etc/profile.d/conda.sh" ]; then
            set +u; source "$base/etc/profile.d/conda.sh"; set -u
            break
        fi
    done
fi
command -v conda >/dev/null 2>&1 \
    || { echo "[maestro] no encontré conda. Cárgalo (module load) o instálalo antes de lanzar." >&2; exit 1; }

# Corre el pipeline sin preguntar (-y). El script 03 lee ENTORNO y MARCADOR de
# parametros.sh y arma el comando de Nextflow con -profile docker y la config del HPC.
bash scripts/03_ejecutar_ampliseq.sh -y
