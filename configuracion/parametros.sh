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
#    MARCADOR (ITS o 16S): parámetros en un .yaml  (sección 3)
# =============================================================================


# 1) Identidad del proyecto
# Nombre corto del proyecto (solo para fines informativos, se guarda en los registros).
PROYECTO="prueba_16S"


# 2) Entorno de ejecución (local o HPC)
# ¿En dónde vas a correr el pipeline?
#   "local" = tu compu. Usa Docker y los núcleos de la máquina.
#   "hpc"   = un clúster con SLURM. Manda las tareas a la cola; corren con Docker
#             en los nodos que lo tienen (en OMICA: nodo27 y nodo28).
# Si lo dejas vacío, el script te preguntará al arrancar (00, 02 y 03).
# Cada entorno tiene su propio archivo de recursos (ver sección 9).
ENTORNO="local"


# 3) Marcador a analizar (ITS o 16S)
# Qué amplicón vas a analizar:
#   "its" = hongos (región ITS, base UNITE).
#   "16s" = procariotas (gen 16S rRNA, base SILVA).
# Si lo dejas vacío, el script te preguntará al arrancar (02 y 03).
# Los parámetros de cada marcador (primers, base de datos, región) viven en su
# propio archivo .yaml; edítalos ahí, no aquí (ver sección 9).
MARCADOR="16s"


# 4) Motor de ejecución (cómo se aíslan los programas)
# Con "auto" el motor es Docker en local y en HPC (lo predeterminado). Solo
# cámbialo si quieres forzar otro:
#   "docker"      = contenedores Docker (local con integración WSL; en HPC corre
#                   en los nodos de cómputo con Docker).
#   "singularity" = contenedores Singularity (alternativa en HPC).
#   "apptainer"   = sucesor de Singularity (alternativa en HPC).
#   "conda"       = un entorno conda por herramienta, sin contenedor (más lento).
MOTOR="auto"

# Entorno conda con Nextflow + Java que crea el script 00. Rara vez se cambia.
ENV_LANZADOR="ampliseq-lanzador"


# 5) Versiones ancladas (clave para la reproducibilidad)
VERSION_PIPELINE="2.17.0"     # versión de nf-core/ampliseq
VERSION_NEXTFLOW=""           # Nextflow: vacío instala siempre la más reciente; ampliseq 2.17.0 pide >=25.04.8


# 6) Datos de entrada (los FASTQ de secuenciación)
# Carpeta con los FASTQ crudos (.fastq.gz).
CARPETA_FASTQ="datos/crudos"

# Diseño de las lecturas:
#   "paired" = pareadas (R1 + R2). Lo normal en Illumina.
#   "single" = individuales (solo R1).
DISENO_LECTURAS="paired"

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
# Carpeta donde se guardan todos los resultados.
SALIDA="resultados"


# 9) Archivos de cada decisión (rara vez se cambian las rutas)
# Recursos por entorno (sección 2); el script elige según ENTORNO.
CONFIG_LOCAL="configuracion/recursos_local.config"
CONFIG_HPC="configuracion/recursos_hpc.config"

# Parámetros por marcador (sección 3); el script elige según MARCADOR.
CONFIG_ITS="configuracion/marcador_its.yaml"
CONFIG_16S="configuracion/marcador_16s.yaml"


# 10) Parámetros extra (avanzado, opcional)
# Cualquier bandera adicional de nf-core/ampliseq, tal cual. Ejemplos útiles:
#   "--truncq 4"                 → corta lecturas con calidad <= 4 (útil en ITS)
#   "--ignore_failed_trimming"   → no abortar si una muestra pierde sus lecturas
#   "--max_ee 2"                 → filtro de error esperado de DADA2
EXTRA_PARAMS=""
