#!/usr/bin/env bash
# =============================================================================
#  03_ejecutar_ampliseq.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Ejecuta el pipeline nf-core/ampliseq. Lee las dos decisiones de
#  configuracion/parametros.sh (entorno y marcador) y lanza Nextflow con la
#  versión fija:
#    entorno: perfil y recursos (-profile / -c recursos_<entorno>.config)
#    marcador: parámetros del análisis (-params-file marcador_<marcador>.yaml)
#  Guarda el comando exacto, el log y una copia de los parámetros usados.
#
#  Uso:   bash scripts/03_ejecutar_ampliseq.sh
#         bash scripts/03_ejecutar_ampliseq.sh --entorno hpc   (sobreescribe parametros.sh)
#         bash scripts/03_ejecutar_ampliseq.sh --proyecto corrida2  (sobreescribe parametros.sh)
#         bash scripts/03_ejecutar_ampliseq.sh --marcador its   (sobreescribe parametros.sh)
#         bash scripts/03_ejecutar_ampliseq.sh --diseno single  (sobreescribe parametros.sh)
#         bash scripts/03_ejecutar_ampliseq.sh --dry-run   (solo prepara, no corre)
#         bash scripts/03_ejecutar_ampliseq.sh -y          (no pide confirmación)
#         bash scripts/03_ejecutar_ampliseq.sh --help      (muestra la ayuda)
# =============================================================================
set -euo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"

# Reutilizamos $SELLO para que la evidencia de la corrida comparta la marca de tiempo
source "scripts/lib/registro.sh"
source "scripts/lib/entorno.sh"
source "scripts/lib/marcador.sh"

# Ayuda de la línea de comandos
mostrar_ayuda() {
    cat <<'AYUDA'
Uso: bash scripts/03_ejecutar_ampliseq.sh [opciones]

Ejecuta el pipeline nf-core/ampliseq con la configuración de configuracion/parametros.sh.
Las opciones de abajo sobreescriben, solo para esta corrida, lo definido en parametros.sh.

Opciones:
  -e, --entorno  <local|hpc>     Dónde correr el pipeline. Sobreescribe ENTORNO de
                                 parametros.sh (y con él el archivo de recursos .config).
  -p, --proyecto <nombre>        Nombre del proyecto. Sobreescribe PROYECTO de
                                 parametros.sh (y con él las carpetas de resultados y logs).
  -m, --marcador <its|16s|18s>   Marcador a analizar. Sobreescribe MARCADOR de
                                 parametros.sh (y con él el archivo de parámetros .yaml).
  -d, --diseno <paired|single>   Diseño de lecturas. Sobreescribe DISENO_LECTURAS de
                                 parametros.sh (pareado o single-end).
      --dry-run                  Solo prepara y muestra el comando, no corre Nextflow.
  -y, --yes                      No pide confirmación de marcador y primers.
  -h, --help                     Muestra esta ayuda y termina.

Ejemplos:
  bash scripts/03_ejecutar_ampliseq.sh
  bash scripts/03_ejecutar_ampliseq.sh --entorno hpc --proyecto corrida2
  bash scripts/03_ejecutar_ampliseq.sh -m its -d single --dry-run
AYUDA
}

# Opciones de línea de comandos. Las sobreescrituras se aplican solo a esta corrida,
# parametros.sh no se toca. Capturamos los overrides antes de abrir el log porque
# --proyecto cambia la carpeta de logs (DIR_LOGS).
DRY_RUN="no"; ASUMIR_SI="no"
PROYECTO_OVERRIDE=""; ENTORNO_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)     mostrar_ayuda; exit 0 ;;
        --dry-run)     DRY_RUN="si" ;;
        -y|--yes)      ASUMIR_SI="si" ;;
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
        -m|--marcador)
            shift; [ $# -gt 0 ] || { log_error "--marcador necesita un valor (its, 16s o 18s)"; exit 1; }
            MARCADOR="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" ;;
        --marcador=*)
            MARCADOR="$(printf '%s' "${1#*=}" | tr '[:upper:]' '[:lower:]')" ;;
        -d|--diseno)
            shift; [ $# -gt 0 ] || { log_error "--diseno necesita un valor (paired o single)"; exit 1; }
            DISENO_LECTURAS="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" ;;
        --diseno=*)
            DISENO_LECTURAS="$(printf '%s' "${1#*=}" | tr '[:upper:]' '[:lower:]')" ;;
        *) log_error "Argumento desconocido: '$1' (usa --entorno, --proyecto, --marcador, --diseno, --dry-run, -y o --help)"; exit 1 ;;
    esac
    shift
done

# Aplicamos los overrides sobre lo que trajo parametros.sh. El de --proyecto recalcula
# las carpetas derivadas (resultados/ y logs/) igual que parametros.sh, para que toda la
# evidencia de esta corrida quede bajo el proyecto indicado.
[ -n "$ENTORNO_OVERRIDE" ] && ENTORNO="$ENTORNO_OVERRIDE"
if [ -n "$PROYECTO_OVERRIDE" ]; then
    PROYECTO="$PROYECTO_OVERRIDE"
    SALIDA="resultados/$PROYECTO"
    DIR_LOGS="logs/$PROYECTO"
fi

iniciar_registro "03_ejecutar_ampliseq"

# Definimos el entorno donde correrá el pipeline y el marcador a analizar
seleccionar_entorno    # fija MOTOR y CONFIG_RECURSOS
seleccionar_marcador   # fija CONFIG_MARCADOR (respeta el --marcador de arriba si se pasó)
activar_trap_errores

# Activamos el entorno con Nextflow y Java. En --dry-run no se corre Nextflow, así
# que nos saltamos esto para poder revisar el comando sin tener el entorno listo.
if [ "$DRY_RUN" != "si" ]; then
    if command -v conda >/dev/null 2>&1; then
        source "$(dirname "$(dirname "${CONDA_EXE:-$(command -v conda)}")")/etc/profile.d/conda.sh"
        conda activate "$ENV_LANZADOR" 2>/dev/null \
            || { log_error "no existe el entorno '$ENV_LANZADOR'. Corre antes: bash scripts/00_instalar_dependencias.sh"; exit 1; }
    fi
    command -v nextflow >/dev/null 2>&1 || { log_error "Nextflow no disponible. Corre: bash scripts/00_instalar_dependencias.sh"; exit 1; }
fi

# Cachés de Nextflow. Con motor apptainer o singularity, las imágenes .sif y las bases
# taxonómicas se guardan y reutilizan en referencias/ (imagenes/ y bases/, ver DIR_REFERENCIAS
# en parametros.sh): el pipeline las baja una vez y en las siguientes corridas las relee. En
# docker y conda no aplica, queda una ruta local por defecto.
DIR_BASES_REF=""
if [ "$MOTOR" = "apptainer" ] || [ "$MOTOR" = "singularity" ]; then
    DIR_REFERENCIAS="${DIR_REFERENCIAS:-$DIR_PROYECTO/referencias}"
    export NXF_SINGULARITY_CACHEDIR="$DIR_REFERENCIAS/imagenes"
    export NXF_APPTAINER_CACHEDIR="$NXF_SINGULARITY_CACHEDIR"
    DIR_BASES_REF="$DIR_REFERENCIAS/bases"
else
    export NXF_SINGULARITY_CACHEDIR="$DIR_PROYECTO/.cache/singularity"
fi
export NXF_CONDA_CACHEDIR="$DIR_PROYECTO/.cache/conda"
mkdir -p "$NXF_CONDA_CACHEDIR" "$DIR_LOGS" "$SALIDA"

# La caché de imágenes (referencias/imagenes con apptainer o singularity) puede estar en una
# ruta compartida. Si no tiene permiso de escritura, avisamos claro en lugar del crudo
# "Permission denied" del mkdir, y damos las dos opciones.
if ! mkdir -p "$NXF_SINGULARITY_CACHEDIR" 2>/dev/null; then
    log_error "No puedo crear la caché de imágenes: $NXF_SINGULARITY_CACHEDIR"
    log_error "  Te falta permiso de escritura ahí. Para resolver, hay dos opciones:"
    log_error "    1) Apunta DIR_REFERENCIAS (parametros.sh) a una carpeta tuya con escritura (en HPC, LUSTRE)."
    log_error "    2) Usa MOTOR=docker: en OMICA no necesita esta caché (las imágenes se jalan en nodo27/28)."
    exit 1
fi

# Con apptainer o singularity, la carpeta de bases que el pipeline llena y reutiliza
# (ref_taxonomy_storage).
if { [ "$MOTOR" = "apptainer" ] || [ "$MOTOR" = "singularity" ]; } && ! mkdir -p "$DIR_BASES_REF" 2>/dev/null; then
    log_error "No puedo crear la carpeta de bases: $DIR_BASES_REF"
    log_error "  Te falta permiso de escritura ahí. Modifica DIR_REFERENCIAS (parametros.sh) para que dirija a una"
    log_error "  carpeta tuya con escritura (en HPC, una ruta compartida en LUSTRE)."
    exit 1
fi

# 1) Validaciones básicas
case "$MOTOR" in
    docker|singularity|apptainer|conda) : ;;
    *) log_error "MOTOR no válido: '$MOTOR' (usa docker, singularity, apptainer o conda)"; exit 1 ;;
esac
case "$DISENO_LECTURAS" in
    paired|single) : ;;
    *) log_error "DISENO_LECTURAS no válido: '$DISENO_LECTURAS' (usa paired o single)"; exit 1 ;;
esac

# Las comprobaciones de motor y caché solo importan cuando el script se corre de verdad. En el
# --dry-run las omitimos para poder revisar el comando sin que Docker ni la caché estén listos.
if [ "$DRY_RUN" != "si" ]; then
    # Que el motor responda antes de empezar. En HPC el maestro (nodo5/27/28) solo
    # manda las tareas a SLURM y el motor corre en los nodos de cómputo (nodo27 y nodo28),
    # así que aquí solo se exige 'sbatch'. En local el motor sí corre en esta máquina.
    if [ "$ENTORNO" = "hpc" ]; then
        command -v sbatch >/dev/null 2>&1 \
            || { log_error "ENTORNO=hpc pero no encontré 'sbatch'. Lanza desde un nodo del clúster (p. ej. nodo5)."; exit 1; }
        case "$MOTOR" in
            docker)
                log_info "Docker corre en los nodos de cómputo (nodo27, nodo28), el job maestro solo orquesta." ;;
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

    # En HPC el maestro puede caer en un nodo de cómputo (nodo27/nodo28), que generalmente no
    # tienen acceso a internet, así que corremos Nextflow offline y usamos el pipeline ya descargado en
    # la caché. Ese precargado lo hace el script 00 en el nodo interactivo (el único con
    # internet). Sin esto Nextflow intenta bajarlo y falla con "Unknown project".
    if [ "$ENTORNO" = "hpc" ]; then
        export NXF_OFFLINE='true'
        # Verificamos contra la caché real de Nextflow (su ubicación depende de NXF_HOME).
        if ! nextflow list 2>/dev/null | grep -qx "nf-core/ampliseq"; then
            log_error "nf-core/ampliseq no aparece en la caché de Nextflow ('nextflow list' no lo encuentra)."
            log_error "  Los nodos de cómputo no tienen internet. Precárgalo en el nodo interactivo:"
            log_error "    conda activate $ENV_LANZADOR && NXF_OFFLINE=false nextflow pull nf-core/ampliseq -r $VERSION_PIPELINE"
            log_error "  Mira dónde quedó con: nextflow info nf-core/ampliseq"
            exit 1
        fi
        log_info "Modo offline (NXF_OFFLINE=true); nf-core/ampliseq disponible en la caché de Nextflow."

        # Con apptainer/singularity las imágenes .sif deben estar precargadas en la caché
        # compartida, en los nodos de cómputo sin internet no se pueden bajar al vuelo.
        if [ "$MOTOR" = "apptainer" ] || [ "$MOTOR" = "singularity" ]; then
            if [ -z "$(ls -A "$NXF_SINGULARITY_CACHEDIR" 2>/dev/null)" ]; then
                log_error "La caché de imágenes está vacía: $NXF_SINGULARITY_CACHEDIR"
                log_error "  Precárgalas en el nodo interactivo (con internet):"
                log_error "    bash scripts/precargar_imagenes_apptainer_hpc.sh"
                exit 1
            fi
            log_info "Imágenes de contenedor desde la caché: $NXF_SINGULARITY_CACHEDIR"
        fi

        # Con apptainer o singularity las bases también deben estar precargadas para correr
        # offline (los nodos no tienen internet). Si usas dada_ref_tax_custom con tus propios
        # archivos, puedes ignorar este aviso.
        if { [ "$MOTOR" = "apptainer" ] || [ "$MOTOR" = "singularity" ]; } && [ -z "$(ls -A "$DIR_BASES_REF" 2>/dev/null)" ]; then
            log_warn "La carpeta de bases está vacía: $DIR_BASES_REF"
            log_warn "  Si el marcador baja la base por nombre (dada_ref_taxonomy), precárgala en el"
            log_warn "  nodo interactivo: bash scripts/precargar_imagenes_apptainer_hpc.sh"
        fi
    fi
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
    # En diseño pareado la hoja debe traer la columna fastq_2 con datos en todas
    # las muestras. Si falta, ampliseq aborta.
    if [ "$DISENO_LECTURAS" = "paired" ]; then
        case "$(head -n1 "$SAMPLESHEET")" in
            *$'\t'fastq_2*) : ;;
            *) log_error "DISENO_LECTURAS=paired pero $SAMPLESHEET no tiene columna fastq_2."
               log_error "  Regenérala con DISENO_LECTURAS=paired (bash scripts/01_generar_samplesheet.sh) o usa single."
               exit 1 ;;
        esac
        sin_r2="$(awk -F'\t' 'NR>1 && $1!="" && $3=="" {c++} END{print c+0}' "$SAMPLESHEET")"
        [ "$sin_r2" -eq 0 ] || { log_error "DISENO_LECTURAS=paired pero $sin_r2 muestra(s) sin fastq_2 en $SAMPLESHEET. Revisa la hoja o regenérala."; exit 1; }
    fi
    ENTRADA=( --input "$SAMPLESHEET" )
else
    ENTRADA=( --input_folder "$CARPETA_FASTQ" )
fi

# 4) Preparamos el params-file de la corrida: copia del YAML del marcador y los
#    parámetros de parametros.sh. Pasamos todo a través de params-file para que
#    nf-schema reciba el tipo correcto y para que el YAML quede como evidencia completa de la
#    corrida.
# Helpers: vuelcan la variable solo si tiene valor, con el formato YAML que toca.
emitir_bool() { if [ "${2:-no}" = "si" ]; then echo "$1: true"; fi; }    # toggle si/no → 'clave: true'
emitir_num()  { if [ -n "${2:-}" ]; then echo "$1: $2"; fi; }            # número, sin comillas
emitir_str()  { if [ -n "${2:-}" ]; then echo "$1: \"$2\""; fi; }        # cadena, entre comillas

PARAMS_RUN="$SALIDA/params_usados_${SELLO}.yaml"
cp "$CONFIG_MARCADOR" "$PARAMS_RUN"
{
    echo ""
    echo "# Parámetros añadidos por 03_ejecutar_ampliseq.sh (sello: $SELLO)"
    # Lecturas single-end (solo R1): sin esto ampliseq asume pareado y exige fastq_2
    if [ "$DISENO_LECTURAS" = "single" ]; then echo "single_end: true"; fi
    # Lecturas ITS pareadas: avisa a ampliseq del posible read-through
    if [ "$MARCADOR" = "its" ] && [ "$DISENO_LECTURAS" = "paired" ]; then echo "illumina_pe_its: true"; fi

    # Recorte de primers (cutadapt)
    emitir_bool double_primer           "$DOBLE_PRIMER"
    emitir_bool retain_untrimmed        "$RETENER_SIN_PRIMER"
    emitir_num  cutadapt_min_overlap    "$CUTADAPT_MIN_OVERLAP"
    emitir_num  cutadapt_max_error_rate "$CUTADAPT_MAX_ERROR_RATE"
    emitir_bool ignore_failed_trimming  "$IGNORAR_RECORTE_FALLIDO"

    # Recorte y filtrado de calidad (DADA2). trunclenr solo aplica a pareadas
    emitir_num  trunclenf  "$TRUNCLENF"
    if [ "$DISENO_LECTURAS" = "paired" ]; then emitir_num trunclenr "$TRUNCLENR"; fi
    emitir_num  trunc_qmin "$TRUNC_QMIN"
    emitir_num  trunc_rmin "$TRUNC_RMIN"
    emitir_num  max_ee     "$MAX_EE"
    emitir_num  min_len    "$MIN_LEN"
    emitir_num  max_len    "$MAX_LEN"
    emitir_bool ignore_failed_filtering "$IGNORAR_FILTRADO_FALLIDO"

    # Cálculo de ASVs (DADA2)
    emitir_str  sample_inference "$SAMPLE_INFERENCE"

    # Posprocesamiento de ASVs
    emitir_bool vsearch_cluster    "$VSEARCH_CLUSTER"
    emitir_num  vsearch_cluster_id "$VSEARCH_CLUSTER_ID"
    emitir_str  filter_ssu         "$FILTER_SSU"
    emitir_num  min_len_asv        "$MIN_LEN_ASV"
    emitir_num  max_len_asv        "$MAX_LEN_ASV"
    emitir_bool filter_codons      "$FILTER_CODONS"
    emitir_num  orf_start          "$ORF_START"
    emitir_num  orf_end            "$ORF_END"
    emitir_str  stop_codons        "$STOP_CODONS"

    # Filtrado de ASVs por taxonomía y abundancia
    emitir_str  exclude_taxa  "$EXCLUDE_TAXA"
    emitir_num  min_frequency "$MIN_FREQUENCY"
    emitir_num  min_samples   "$MIN_SAMPLES"

    # Análisis posteriores (diversidad y abundancia)
    emitir_str  metadata_category           "$METADATA_CATEGORY"
    emitir_str  metadata_category_barplot   "$METADATA_CATEGORY_BARPLOT"
    emitir_num  diversity_rarefaction_depth "$DIVERSITY_RAREFACTION_DEPTH"
    emitir_num  tax_agglom_min "$TAX_AGGLOM_MIN"
    emitir_num  tax_agglom_max "$TAX_AGGLOM_MAX"

    # Reporte de resumen
    emitir_str  report_title "$REPORT_TITLE"

    # Guardar artefactos intermedios de QIIME2 (.qza/.qzv)
    emitir_bool save_intermediates "$GUARDAR_INTERMEDIOS"

    # Omitir pasos específicos (toggles OMITIR_* de parametros.sh; comentados por defecto)
    emitir_bool skip_fastqc            "${OMITIR_FASTQC:-no}"
    emitir_bool skip_cutadapt          "${OMITIR_CUTADAPT:-no}"
    emitir_bool skip_dada_quality      "${OMITIR_DADA_QUALITY:-no}"
    emitir_bool skip_barrnap           "${OMITIR_BARRNAP:-no}"
    emitir_bool skip_qiime             "${OMITIR_QIIME:-no}"
    emitir_bool skip_qiime_downstream  "${OMITIR_QIIME_DOWNSTREAM:-no}"
    emitir_bool skip_taxonomy          "${OMITIR_TAXONOMY:-no}"
    emitir_bool skip_dada_taxonomy     "${OMITIR_DADA_TAXONOMY:-no}"
    emitir_bool skip_dada_addspecies   "${OMITIR_DADA_ADDSPECIES:-no}"
    emitir_bool skip_barplot           "${OMITIR_BARPLOT:-no}"
    emitir_bool skip_abundance_tables  "${OMITIR_ABUNDANCE_TABLES:-no}"
    emitir_bool skip_alpha_rarefaction "${OMITIR_ALPHA_RAREFACTION:-no}"
    emitir_bool skip_diversity_indices "${OMITIR_DIVERSITY_INDICES:-no}"
    emitir_bool skip_phyloseq          "${OMITIR_PHYLOSEQ:-no}"
    emitir_bool skip_tse               "${OMITIR_TSE:-no}"
    emitir_bool skip_multiqc           "${OMITIR_MULTIQC:-no}"
    emitir_bool skip_report            "${OMITIR_REPORT:-no}"
} >> "$PARAMS_RUN"

# 5) Ensamblamos el comando de Nextflow para correr el pipeline
#   los recursos son definidos por -c (entorno) y los parámetros por -params-file (marcador, toggles y demás)
CMD=( nextflow run nf-core/ampliseq
      -r "$VERSION_PIPELINE"
      -profile "$MOTOR"
      -params-file "$PARAMS_RUN"
      -c "$CONFIG_RECURSOS"
      "${ENTRADA[@]}"
      --outdir "$SALIDA"
      -resume
      -ansi-log false )

# Con apptainer o singularity, el pipeline guarda y reutiliza las bases taxonómicas en
# referencias/bases (storeDir nativo de ampliseq): las baja una vez y en las siguientes
# corridas las relee. En un HPC sin internet en los nodos, precárgalas antes con
# precargar_imagenes_apptainer_hpc.sh.
if [ "$MOTOR" = "apptainer" ] || [ "$MOTOR" = "singularity" ]; then
    CMD+=( --ref_taxonomy_storage "$DIR_BASES_REF" )
fi

# Metadatos (solo si existe el archivo)
if [ -n "$METADATA" ] && [ -f "$METADATA" ]; then
    CMD+=( --metadata "$METADATA" )
else
    log_warn "No se encontraron metadatos. Se omitirán los análisis de diversidad de QIIME2."
fi
# Correo para el resumen de fin de corrida (solo si se definió)
[ -n "$EMAIL" ] && CMD+=( --email "$EMAIL" )
# Parámetros extra del usuario (avanzado)
if [ -n "$EXTRA_PARAMS" ]; then
    # shellcheck disable=SC2206
    CMD+=( $EXTRA_PARAMS )
fi

# 6) Mostramos el resumen
cabecera_registro "EJECUCIÓN DE nf-core/ampliseq."
log_info "  Pipeline:        nf-core/ampliseq r${VERSION_PIPELINE}"
log_info "  Entorno:         $ENTORNO  (recursos: $CONFIG_RECURSOS)"
log_info "  Marcador:        $MARCADOR  (parámetros: $CONFIG_MARCADOR → $PARAMS_RUN)"
log_info "  Diseño:          $DISENO_LECTURAS"
log_info "  Motor:           $MOTOR"
log_info "  Entrada:         ${ENTRADA[*]}"
log_info "  Primers:         FW=$FW${RV:+  RV=$RV}"
[ "$MARCADOR" = "its" ] && log_info "  Región ITS:      $REGION"
log_info "  Taxonomía:       $TAXONOMIA"
log_info "  Metadatos:       ${METADATA:-(ninguno)}"
log_info "  Correo:          ${EMAIL:-(ninguno)}"
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
