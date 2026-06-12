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
# (resultados/<PROYECTO>/ y logs/<PROYECTO>/, ver sección 8). Usa un nombre sin espacios.
PROYECTO="prueba_ITS"


# 2) Entorno de ejecución (local o HPC)
# ¿En dónde vas a correr el pipeline?
#   "local" = tu compu. Usa Docker y los núcleos de la máquina.
#   "hpc"   = un clúster con SLURM. Manda las tareas a la cola, corren con Docker
#             en los nodos que lo tienen (en OMICA: nodo27 y nodo28).
# Si lo dejas vacío, el script te preguntará al arrancar (00, 02 y 03).
# Cada entorno tiene su propio archivo de recursos (ver sección 9).
ENTORNO="local"

# Nodos donde puede correr el job maestro en el HPC, en orden de preferencia. El
# maestro es ligero (2 CPU, 4 GB) y puede compartir nodo27/nodo28 con las tareas.
# scripts/lanzar_hpc.sh toma el primero con hueco. En OMICA son los nodos con
# Docker: nodo5, nodo27 y nodo28.
NODOS_MAESTRO="nodo5 nodo27 nodo28"


# 3) Marcador a analizar (ITS, 16S o 18S)
# Qué amplicón vas a analizar:
#   "its" = hongos (región ITS).
#   "16s" = procariotas (gen 16S rDNA).
#   "18s" = eucariotas (gen 18S rDNA).
# Si lo dejas vacío, el script te preguntará al arrancar (02 y 03).
# Los parámetros de cada marcador (primers, base de datos, región) viven en su
# propio archivo .yaml. Edítalos ahí, no aquí (ver sección 9).
MARCADOR="its"


# 4) Motor de ejecución (cómo se aíslan los programas)
# Con "auto" el motor es Docker en local y en HPC (lo predeterminado). Solo
# cámbialo si quieres forzar otro:
#   "docker"      = contenedores Docker (local con integración WSL, en HPC corre
#                   en los nodos de cómputo con Docker).
#   "singularity" = contenedores Singularity (alternativa en HPC).
#   "apptainer"   = sucesor de Singularity. Recomendado en un HPC sin internet: las
#                   imágenes .sif se precargan una vez y viven en LUSTRE compartido.
#   "conda"       = un entorno conda por herramienta, sin contenedor (más lento).
MOTOR="auto"

# Entorno conda con Nextflow + Java que crea el script 00.
ENV_LANZADOR="ampliseq-lanzador"

# HPC de OMICA: internet general bloqueado, pero los nodos con Docker (nodo27/28)
# SÍ alcanzan el registro de contenedores (quay.io), así que con MOTOR=docker
# Nextflow jala las imágenes al correr. Como la conectividad es intermitente,
# conviene precargarlas una vez con scripts/precargar_imagenes_docker_hpc.sh.
# Nodos con Docker donde corren las tareas (debe coincidir con --nodelist de
# recursos_hpc.config).
NODOS_TAREAS_DOCKER="nodo27 nodo28"

# Solo para motor apptainer/singularity (si IT lo instala): las imágenes .sif y las
# bases se precargan una vez en el nodo interactivo y viven en LUSTRE compartido.
#   DIR_BASES_HPC        carpeta raíz de bases de datos en LUSTRE
#   DIR_CACHE_SINGULARITY carpeta de imágenes .sif (la llena scripts/precargar_imagenes_hpc.sh)
# Ajústalas a una ruta donde tengas permiso de escritura.
DIR_BASES_HPC="/LUSTRE/bioinformatica_data/BD/metagenomica"
DIR_CACHE_SINGULARITY="$DIR_BASES_HPC/cache_singularity_ampliseq"


# 5) Versiones ancladas (clave para la reproducibilidad)
VERSION_PIPELINE="2.17.0"     # versión de nf-core/ampliseq
VERSION_NEXTFLOW=""           # Nextflow: vacío instala siempre la más reciente, ampliseq 2.17.0 pide >=25.04.8


# 6) Datos de entrada (los FASTQ de secuenciación)
# Carpeta con los FASTQ crudos (.fastq.gz).
CARPETA_FASTQ="datos/crudos"

# Diseño de las lecturas:
#   "paired" = pareadas (R1 + R2). Lo normal en Illumina.
#   "single" = individuales (solo R1).
DISENO_LECTURAS="single"

# Hoja de muestras que genera el script 01 a partir de CARPETA_FASTQ.
SAMPLESHEET="configuracion/samplesheet.tsv"

# ¿Usar la hoja de muestras (recomendado) o la carpeta directamente?
#   "si" = usa SAMPLESHEET   |   "no" = usa CARPETA_FASTQ
USAR_SAMPLESHEET="si"

# ¿Correr cutadapt dos veces para quitar primers dobles/concatenados?
#   "si" → activa --double_primer (útil si quedan primers residuales en el reporte)
DOBLE_PRIMER="no"


# 7) Metadatos (opcional, recomendado para análisis de diversidad)
# Tabla de metadatos (TSV, primera columna con encabezado "ID"). Si la dejas
# vacía (""), se omiten los análisis de diversidad de QIIME2. Hay una plantilla
# en metadatos/metadatos.tsv.ejemplo
METADATA=""


# 8) Salida
# Carpeta de resultados. Cada proyecto va en su propia subcarpeta (resultados/<PROYECTO>/)
# para que las corridas de distintos proyectos no se mezclen ni se sobrescriban.
# El nombre lo toma de PROYECTO (sección 1).
SALIDA="resultados/$PROYECTO"

# Carpeta de logs de los scripts (.out, .err, comando y versiones), también por proyecto.
DIR_LOGS="logs/$PROYECTO"


# 9) Archivos de cada decisión (rara vez se cambian las rutas)
# Recursos por entorno (sección 2); el script elige según ENTORNO.
CONFIG_LOCAL="configuracion/recursos_local.config"
CONFIG_HPC="configuracion/recursos_hpc.config"

# Parámetros por marcador (sección 3); el script elige según MARCADOR.
CONFIG_ITS="configuracion/marcador_its.yaml"
CONFIG_16S="configuracion/marcador_16s.yaml"
CONFIG_18S="configuracion/marcador_18s.yaml"


# 10) Parámetros extra (avanzado, opcional)
# Cualquier bandera adicional de nf-core/ampliseq, tal cual. Ejemplos útiles:
#   "--truncq 4"                 → corta lecturas con calidad <= 4 (útil en ITS)
#   "--ignore_failed_trimming"   → no abortar si una muestra pierde sus lecturas
#   "--max_ee 2"                 → filtro de error esperado de DADA2
EXTRA_PARAMS=""
