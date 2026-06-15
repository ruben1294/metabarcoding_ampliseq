# =============================================================================
#  parametros.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Configuración central del flujo. Es el archivo que normalmente editas. Los
#  scripts 00, 01, 02 y 03 leen sus valores desde aquí. Usa  VARIABLE="valor"
#  (sin espacios alrededor del =).
#
#  Dos decisiones importantes gobiernan todo el flujo y cada una tiene su propio archivo:
#    ENTORNO  (local o HPC): recursos en un .config  (sección 2)
#    MARCADOR (ITS, 16S o 18S): parámetros en un .yaml  (sección 3)
# =============================================================================


# 1) Identidad del proyecto
# Nombre corto del proyecto. Nombra las subcarpetas de resultados y logs
# (resultados/<PROYECTO>/ y logs/<PROYECTO>/, ver sección 15). Usa un nombre sin espacios.
PROYECTO="prueba_16S"


# 2) Entorno de ejecución (local o HPC)
# ¿En dónde vas a correr el pipeline?
#   "local" = tu compu. Usa Docker y los núcleos de la máquina.
#   "hpc"   = un clúster con SLURM. Manda las tareas a la cola, corren con Docker
#             en los nodos que lo tienen (en OMICA: nodo27 y nodo28).
# Si lo dejas vacío, el script te preguntará al arrancar (00, 02 y 03).
# Cada entorno tiene su propio archivo de recursos (ver sección 16).
ENTORNO="local"

# Nodos donde puede correr el job maestro en el HPC, en orden de preferencia. El
# maestro es ligero (2 CPU, 4 GB) y puede compartir con nodo27 y nodo28 con las tareas.
# scripts/lanzar_hpc.sh elige el primer nodo vacío. En OMICA son los nodos con
# Docker: nodo5, nodo27 y nodo28.
NODOS_MAESTRO="nodo5 nodo27 nodo28"

# Cuenta (grupo) y partición/cola de SLURM. Son tu identidad de cobro en el clúster:
# si SLURM responde "Invalid account or account/partition combination", aquí se cambia.
# En OMICA (CICESE) el grupo es 'metagenomica' y la partición 'cicese'; cámbialos al
# tuyo (p. ej. CUENTA_SLURM="la_paz"). Confírmalos con:
#   sacctmgr show assoc user=$USER format=Account,Partition
# Una sola fuente de verdad: de aquí se propagan a recursos_hpc.config (vía variable
# de entorno), a lanzar_hpc.sh (sbatch) y a precargar_imagenes_docker_hpc.sh (srun).
# Van con 'export' para que Nextflow las pase al .config de recursos.
export CUENTA_SLURM="metagenomica"
export PARTICION_SLURM="cicese"


# 3) Marcador a analizar (ITS, 16S o 18S)
# ¿Qué amplicón vas a analizar?
#   "its" = hongos (región ITS).
#   "16s" = procariotas (gen 16S rDNA).
#   "18s" = eucariotas (gen 18S rDNA).
# Si lo dejas vacío, el script te preguntará al arrancar (02 y 03).
# Los parámetros de cada marcador (primers, base de datos, región) están en su
# propio archivo .yaml. Edítalos ahí, no acá (ver sección 16).
MARCADOR="16s"


# 4) Motor de ejecución (cómo se aíslan los programas)
# Con "auto" el motor es Docker en local y en HPC (lo predeterminado). Solo
# cámbialo si quieres forzar otro:
#   "docker"      = contenedores Docker (local con integración WSL, en HPC corre
#                   en los nodos de cómputo con Docker).
#   "singularity" = contenedores Singularity (alternativa en HPC).
#   "apptainer"   = sucesor de Singularity. Recomendado en un HPC sin internet: las
#                   imágenes .sif se precargan una vez y se guardan en LUSTRE compartido.
#   "conda"       = un entorno conda por herramienta, sin contenedor (más lento).
MOTOR="auto"

# Entorno conda con Nextflow y Java que crea el script 00.
ENV_LANZADOR="ampliseq-lanzador"

# Nodos con Docker donde corren las tareas (debe coincidir con --nodelist de
# recursos_hpc.config).
NODOS_TAREAS_DOCKER="nodo27 nodo28"

# Solo para motor apptainer/singularity: las imágenes .sif y las
# bases se precargan una vez en el nodo interactivo y se guardan en LUSTRE.
#   DIR_BASES_HPC        carpeta raíz de bases de datos en LUSTRE
#   DIR_CACHE_SINGULARITY carpeta de imágenes .sif (la llena scripts/precargar_imagenes_apptainer_hpc.sh)
# Ajústalas a una ruta donde tengas permiso de escritura.
DIR_BASES_HPC="/LUSTRE/bioinformatica_data/BD/metagenomica"
DIR_CACHE_SINGULARITY="$DIR_BASES_HPC/cache_singularity_ampliseq"


# 5) Versiones del pipeline original y de Nextflow
VERSION_PIPELINE="2.17.0"     # versión de nf-core/ampliseq
VERSION_NEXTFLOW=""           # Nextflow: vacío instala siempre la más reciente. El flujo ampliseq 2.17.0 pide >=25.04.8


# 6) Datos de entrada (los FASTQ de secuenciación)
# Carpeta con los FASTQ crudos (.fastq.gz).
CARPETA_FASTQ="datos/crudos"

# Diseño de las lecturas:
#   "paired" = pareadas (R1 + R2).
#   "single" = individuales (solo R1).
DISENO_LECTURAS="paired"

# Hoja de muestras que genera el script 01 a partir de CARPETA_FASTQ.
SAMPLESHEET="configuracion/samplesheet.tsv"

# ¿Usar la hoja de muestras (recomendado) o la carpeta directamente?
#   "si" = usa SAMPLESHEET   |   "no" = usa CARPETA_FASTQ
USAR_SAMPLESHEET="si"

# ¿Correr cutadapt dos veces para quitar primers dobles/concatenados?
#   "si": activa --double_primer
DOBLE_PRIMER="no"

# ¿Conservar las lecturas sin primer en vez de descartarlas? si/no
#   "si": activa --retain_untrimmed
RETENER_SIN_PRIMER="no"

# Solape mínimo (pb) que cutadapt exige para reconocer el primer. --cutadapt_min_overlap
CUTADAPT_MIN_OVERLAP="3"

# Tasa máxima de error que cutadapt tolera al reconocer el primer. --cutadapt_max_error_rate
CUTADAPT_MAX_ERROR_RATE="0.1"

# ¿No abortar si una muestra se queda sin lecturas tras el recorte? si/no
#   "si": activa --ignore_failed_trimming
IGNORAR_RECORTE_FALLIDO="no"


# 7) Recorte y filtrado de calidad de lecturas (DADA2)
# Longitud a la que se truncan las lecturas FW. 0 = sin truncado (auto según TRUNC_QMIN). Depende de la región del marcador a analizar, pero como regla general, se sugiere usar 150 pb e ir ajustando dependiendo de la calidad obtenida. --trunclenf
TRUNCLENF="150"

# Longitud a la que se truncan las lecturas RV (solo pareadas). Depende de la región del marcador a analizar, pero como regla general, se sugiere usar 150 pb e ir ajustando dependiendo de la calidad obtenida. 0 = sin truncado. --trunclenr
TRUNCLENR="150"

# Calidad mínima (phred) para el truncado automático cuando TRUNCLENF/R = 0. --trunc_qmin
TRUNC_QMIN="25"

# Fracción mínima de lecturas que el truncado automático debe conservar. --trunc_rmin
TRUNC_RMIN="0.75"

# Máximo de errores esperados (EE), descarta lecturas por encima. --max_ee
MAX_EE="2"

# Longitud mínima de lectura tras el filtrado. --min_len
MIN_LEN="50"

# Longitud máxima de lectura tras el filtrado, vacío = sin límite. --max_len
MAX_LEN=""

# ¿No abortar si una muestra queda con muy pocas lecturas tras el filtrado? si/no
#   "si": activa --ignore_failed_filtering
IGNORAR_FILTRADO_FALLIDO="no"


# 8) Cálculo de variantes de secuencia (ASV) con DADA2
# Modo de inferencia: independent (cada muestra), pooled (todas juntas) o
# pseudo (intermedio). --sample_inference
SAMPLE_INFERENCE="independent"


# 9) Posprocesamiento de ASVs
# ¿Agrupar ASVs en OTUs por identidad con vsearch? si/no
#   "si": activa --vsearch_cluster
VSEARCH_CLUSTER="no"

# Identidad (0-1) para agrupar con vsearch. --vsearch_cluster_id
VSEARCH_CLUSTER_ID="0.97"

# Filtrar ASVs por SSU rDNA con barrnap, vacío = sin filtro (ej. bac,arc,mito,euk). --filter_ssu
FILTER_SSU=""

# Longitud mínima de ASV (pb); vacío = sin filtro. --min_len_asv
MIN_LEN_ASV=""

# Longitud máxima de ASV (pb), vacío = sin filtro. --max_len_asv
MAX_LEN_ASV=""

# ¿Filtrar ASVs por codones de paro (marcadores codificantes)? si/no
#   "si": activa --filter_codons
FILTER_CODONS="no"

# Inicio del marco de lectura (ORF) para el filtro de codones. --orf_start
ORF_START="1"

# Fin del marco de lectura (ORF); vacío = hasta el final. --orf_end
ORF_END=""

# Codones de paro para el filtro. --stop_codons
STOP_CODONS="TAA,TAG"


# 10) Filtrado de ASVs por taxonomía y abundancia
# Taxones a excluir (lista separada por comas). --exclude_taxa
EXCLUDE_TAXA="mitochondria,chloroplast"

# Frecuencia (abundancia total) mínima para conservar un ASV. --min_frequency
MIN_FREQUENCY="1"

# Número mínimo de muestras en que debe aparecer un ASV. --min_samples
MIN_SAMPLES="1"


# 11) Metadatos (opcional, recomendado para análisis de diversidad)
# Tabla de metadatos (TSV, primera columna con encabezado "ID"). Si la dejas
# vacía (""), se omiten los análisis de diversidad de QIIME2. Hay una plantilla
# en metadatos/metadatos.tsv.ejemplo
METADATA=""


# 12) Análisis posteriores (diversidad y abundancia, usan los metadatos de arriba)
# Columnas de metadatos para las pruebas estadísticas (lista por comas),
# vacío = ampliseq elige las categorías aptas. --metadata_category
METADATA_CATEGORY=""

# Columnas de metadatos para los barplots de abundancia relativa media (por comas). --metadata_category_barplot
METADATA_CATEGORY_BARPLOT=""

# Profundidad mínima de rarefacción para diversidad, descarta muestras por debajo. --diversity_rarefaction_depth
DIVERSITY_RAREFACTION_DEPTH="500"

# Nivel mínimo de aglomeración taxonómica. --tax_agglom_min
TAX_AGGLOM_MIN="2"

# Nivel máximo de aglomeración taxonómica. --tax_agglom_max
TAX_AGGLOM_MAX="6"


# 13) Reporte de resumen del pipeline
# Título del reporte Markdown final. --report_title
REPORT_TITLE="Reporte de resultados de mi análisis de metabarcoding"


# 14) Omitir pasos específicos (avanzado). Descomenta y pon "si" para saltarte un paso,
#     por defecto no se omite nada. Cada variable activa su bandera --skip_* de ampliseq.
#OMITIR_FASTQC="si"              # --skip_fastqc: control de calidad FastQC
#OMITIR_CUTADAPT="si"           # --skip_cutadapt: recorte de primers (¡no recomendado!)
#OMITIR_DADA_QUALITY="si"       # --skip_dada_quality: control de calidad DADA2 (solo si fijas TRUNCLENF/R)
#OMITIR_BARRNAP="si"            # --skip_barrnap: anotación de SSU rDNA con barrnap
#OMITIR_QIIME="si"              # --skip_qiime: todos los pasos de QIIME2
#OMITIR_QIIME_DOWNSTREAM="si"   # --skip_qiime_downstream: pasos de QIIME2 salvo la clasificación taxonómica
#OMITIR_TAXONOMY="si"           # --skip_taxonomy: la clasificación taxonómica por completo
#OMITIR_DADA_TAXONOMY="si"      # --skip_dada_taxonomy: clasificación taxonómica con DADA2
#OMITIR_DADA_ADDSPECIES="si"    # --skip_dada_addspecies: asignación a especie con DADA2 (baja mucho la RAM)
#OMITIR_BARPLOT="si"            # --skip_barplot: barplots de abundancia
#OMITIR_ABUNDANCE_TABLES="si"   # --skip_abundance_tables: tablas de abundancia relativa
#OMITIR_ALPHA_RAREFACTION="si"  # --skip_alpha_rarefaction: rarefacción alfa
#OMITIR_DIVERSITY_INDICES="si"  # --skip_diversity_indices: diversidad alfa y beta
#OMITIR_PHYLOSEQ="si"           # --skip_phyloseq: exportar objetos phyloseq (R)
#OMITIR_TSE="si"                # --skip_tse: exportar objetos TreeSummarizedExperiment (R)
#OMITIR_MULTIQC="si"            # --skip_multiqc: reporte MultiQC
#OMITIR_REPORT="si"             # --skip_report: reporte Markdown de resumen


# 15) Salida
# Carpeta de resultados. Cada proyecto va en su propia subcarpeta (resultados/<PROYECTO>/).
# El nombre lo toma de PROYECTO (sección 1).
SALIDA="resultados/$PROYECTO"

# Carpeta de logs de los scripts (.out, .err, comando y versiones), también por proyecto.
DIR_LOGS="logs/$PROYECTO"

# ¿Guardar los archivos intermedios de QIIME2 (.qza/.qzv)? si/no
#   "si": activa --save_intermediates
GUARDAR_INTERMEDIOS="si"

# Correo para el resumen que ampliseq manda al terminar.
EMAIL=""


# 16) Archivos de cada decisión (no recomiendo cambiar las rutas)

# Recursos por entorno (sección 2), el script elige según el ENTORNO.
CONFIG_LOCAL="configuracion/recursos_local.config"
CONFIG_HPC="configuracion/recursos_hpc.config"

# Parámetros por marcador (sección 3), el script elige según el MARCADOR.
CONFIG_ITS="configuracion/marcador_its.yaml"
CONFIG_16S="configuracion/marcador_16s.yaml"
CONFIG_18S="configuracion/marcador_18s.yaml"


# 17) Parámetros extra (avanzado, opcional)
# Banderas adicionales de nf-core/ampliseq tal cual, se pasan por CLI y mandan sobre
# el params-file. Si algo ya tiene su variable arriba, edita la variable, no esto.
#   "--pacbio"                    → lecturas PacBio en vez de Illumina
#   "--multiple_sequencing_runs"  → la entrada tiene varias corridas de secuenciación
#   "--picrust"                   → predicción funcional con PICRUSt2
EXTRA_PARAMS=""
