<!--<p align="center">
  <img src="imagenes/cicese.png" alt="CICESE" height="90">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="imagenes/logo_lab_metagenomica.svg" alt="Laboratorio de Metagenómica" height="145">

</p>
-->
# _Metabarcoding_ con nf-core/ampliseq

[![shellcheck](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/shellcheck.yml) [![nextflow-config](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/nextflow-config.yml/badge.svg)](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/nextflow-config.yml) [![tests](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/tests.yml/badge.svg)](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/tests.yml)
 [![DOI](https://zenodo.org/badge/1266027343.svg)](https://doi.org/10.5281/zenodo.20711275)

Flujo de trabajo para hacer un análisis de _metabarcoding_ (también conocido como análisis de amplicones) a partir de secuencias amplificadas por PCR y secuenciadas con la plataforma Illumina, con tres marcadores genéticos posibles a analizar: la región ITS (*Internal Transcribed Spacer*), el gen 16S rDNA o el gen 18S rDNA. Está adaptado para que lo puedas correr local (en tu computadora) o en un HPC con calendarizador. Nextflow, que es un orquestador, tiene una comunicación muy detallada con el calendarizador SLURM.

Usa [nf-core/ampliseq](https://nf-co.re/ampliseq) (v2.18.0), que ejecuta:
control de calidad (FastQC), eliminación de *primers* (cutadapt), inferencia de _Amplicon Sequence Variants_ (ASVs) (DADA2), recorte de la región ITS con ITSx (solo en ITS), inferencia taxonómica y análisis de diversidad (QIIME2), con reportes finales (MultiQC y reporte final).

 El objetivo de este _pipeline_ es llamar a nf-core/ampliseq, construir tu comando de Nextflow y resolver la instalación de dependencias y la definición de parámetros para que puedas correr tu análisis de manera fluida, sencilla y reproducible, sin preocuparte por instalar (casi) nada.

---

## 1. Estructura del proyecto

```
metabarcoding_ampliseq/
├── README.md                          ← este archivo
├── CITATION.cff                       ← cómo citar el repositorio
├── LICENSE                            ← licencia MIT
├── configuracion/
│   ├── parametros.sh                  ← Edita aquí los parámetros para el flujo de trabajo
│   ├── recursos_local.config          ← definición de recursos para correr en local
│   ├── recursos_hpc.config            ← definición de recursos, cola y nodos con Docker del HPC (con SLURM)
│   ├── marcador_its.yaml              ← parámetros del análisis de ITS
│   ├── marcador_16s.yaml              ← parámetros del análisis de 16S
│   ├── marcador_18s.yaml              ← parámetros del análisis de 18S
│   ├── primers_its.tsv                ← catálogo de primers estándar para ITS
│   ├── primers_16s.tsv                ← catálogo de primers estándar 16S
│   ├── primers_18s.tsv                ← catálogo de primers estándar 18S
│   └── samplesheet.tsv                ← (lo genera el script 01)
├── scripts/
│   ├── 00_instalar_dependencias.sh    ← verifica e instala todo lo que falte
│   ├── 01_generar_samplesheet.sh      ← genera la hoja de muestras desde los FASTQ
│   ├── 02_verificar_entorno.sh        ← verifica que todo esté listo
│   ├── 03_ejecutar_ampliseq.sh        ← corre el análisis
│   ├── 04_resumen_tiempos.sh          ← crea la tabla de tiempos por proceso de la corrida
│   ├── lanzar_hpc.sh                  ← lanza el job maestro en el HPC (wrapper)
│   ├── lanzar_hpc.slurm               ← script SLURM del job maestro
│   ├── precargar_imagenes_docker_hpc.sh ← precarga imágenes Docker en los nodos elegidos (HPC)
│   ├── precargar_imagenes_apptainer_hpc.sh ← precarga imágenes .sif y bases en referencias/ (apptainer/singularity)
│   ├── descargar_datos_prueba.sh      ← baja un conjunto pequeño y estándar para probar
│   └── lib/                           ← funciones comunes (registro, entorno y marcador)
├── tests/                             ← pruebas (bats y validación del params-file)
├── .github/workflows/                 ← integración continua (shellcheck, configs de Nextflow y pruebas)
├── datos/crudos/                       ← ⬅️ pon aquí tus FASTQ (.fastq.gz)
├── metadatos/
│   └── metadatos.tsv.ejemplo           ← plantilla de metadatos para QIIME2
├── referencias/                        ← caché de apptainer/singularity
│   ├── imagenes/                       ← imágenes .sif de los contenedores
│   └── bases/                          ← bases de datos taxonómicas que el pipeline descarga
├── resultados/<PROYECTO>/              ← resultados, una subcarpeta por proyecto
└── logs/<PROYECTO>/                    ← logs de cada corrida, también por proyecto
```

---

## 2. Definición de entorno y marcador

Al iniciar, los _scripts_ te preguntan dónde correrás el flujo y qué marcador analizarás, si no las has definido ya. Para no responder cada vez que corres un _script_, defínelas en `configuracion/parametros.sh`, allí es donde editaremos prácticamente todos los parámetros de configuración del _pipeline_. En un HPC es obligatorio definirlas si lanzas el _pipeline_ sin terminal interactiva.

### a) Entorno donde correrá el _pipeline_

- **`local`**: tu computadora. Usa Docker y los recursos de la computadora, con los
  límites de recursos definidos en `configuracion/recursos_local.config`. Probado en una laptop con WSL y Docker Desktop previamente conectado. La arquitectura con esta opción es más sencilla.
- **`hpc`**: un clúster con el calendarizador SLURM. En esta opción, se crea un _job_ maestro que es el orquestador, y este crea _jobs_ hijos que ejecutan las tareas del _pipeline_, todo manejado por SLURM. Manda cada tarea a la cola y la corre con Docker, Apptainer o Singularity, usando los límites definidos en `configuracion/recursos_hpc.config`.

#### HPC de OMICA

En el HPC de OMICA (CICESE) el motor es Docker, pero actualmente este solo está instalado en los nodos: nodo5, nodo27 y nodo28. La arquitectura elegida es que el _job_ maestro corre en uno de esos tres nodos y nodo27 y nodo28 se usan para lanzar los _jobs_ hijos que realizan el análisis del _pipeline_. El  _job_ maestro es un orquestador que pide pocos recursos, entonces puede compartir nodo27 o nodo28 con las tareas. Todo esto ya viene configurado en `recursos_hpc.config`, en `scripts/lanzar_hpc.slurm` y en `NODOS_MAESTRO` (parametros.sh). Ajusta tu cuenta, partición o los nodos si tu clúster es diferente.

En OMICA el internet general está bloqueado, pero los nodos con Docker (nodo5/nodo27/nodo28) sí pueden conectarse con el registro de contenedores (`quay.io`) usados en el _pipeline_. El *job* maestro corre en modo *offline* para el *pipeline* (`NXF_OFFLINE=true`, que se define automáticamente en `ENTORNO=hpc` y usa la copia cacheada), y las imágenes de los contenedores a usar se jalan al correr. Para correr el _pipeline_ allí, los pasos son:

1. ***Pipeline*** (lo hace el script 00, en el nodo interactivo con internet): `NXF_OFFLINE=false nextflow pull nf-core/ampliseq -r 2.18.0`.
2. **Imágenes de contenedor** (`MOTOR="docker"`, el predeterminado): recomiendo precargar las imágenes una vez en cada nodo con: `bash scripts/precargar_imagenes_docker_hpc.sh`. Ese paso también deja cacheados los *plugins* de Nextflow que el *job* maestro usará en modo *offline*. Si en vez de Docker usas Apptainer o Singularity, precarga las imágenes y las bases de una sola vez en el nodo interactivo con `bash scripts/precargar_imagenes_apptainer_hpc.sh`, que las deja ordenadas en `referencias/`.
3. **Bases de datos taxonómicas**: si los nodos no pueden conectarse con los servidores de las bases (UNITE, SILVA, PR2, etc.), tenlas en una carpeta de LUSTRE que los nodos de cómputo sí vean y dirige el archivo YAML del marcador a esos archivos locales (`dada_ref_tax_custom`, etc.). Esa carpeta es `DIR_BASES_HPC` (parametros.sh): úsala tal cual si tu clúster ya tiene las bases montadas ahí, o precárgalas tú una vez en el nodo interactivo (para eso necesitas permiso de escritura en ella). Cada `marcador_*.yaml` trae ya la estructura comentada y el comando para sacar la URL o el archivo exacto del *pipeline*, todo listo solo para que definas las rutas reales.

 Si los nodos de cómputo no ven la carpeta del proyecto o no puedes escribir en ella, modifica la ruta `DIR_REFERENCIAS` (parametros.sh) a una ruta tuya en LUSTRE en donde tengas permisos de escritura.

> Para que puedas usar Docker, necesitas pedir a la administración que te agreguen a los usuarios con permisos para usar Docker (sudo usermod -aG docker tu_usuario).

> A la fecha, Apptainer y Singularity no funcionan en los nodos de cómputo de OMICA. El Apptainer sin privilegios (el que se instala por conda) necesita *user namespaces* del kernel, y OMICA los tiene deshabilitados (`user.max_user_namespaces = 0`), sin un Apptainer *setuid* del sistema como alternativa. El error que verás es `Failed to create user namespace: user namespace disabled`. Para usarlos, necesitamos que la administración instale Apptainer *setuid* o suba `user.max_user_namespaces`. Mientras tanto, en OMICA usa `MOTOR="docker"`.

### b) Marcador genético a analizar

- **`its`**: hongos. Región ITS, base de datos predeterminada UNITE. Configura los parámetros (_primers_, base de datos y otros) en `configuracion/marcador_its.yaml`.
- **`16s`**: procariotas. Gen 16S rDNA, base de datos predeterminada SILVA. Configura los parámetros (_primers_, base de datos y otros) en `configuracion/marcador_16s.yaml`.
- **`18s`**: eucariotas. Gen 18S rDNA, base de datos predeterminada PR2. Configura los parámetros (_primers_, base de datos y otros) en `configuracion/marcador_18s.yaml`.

Cada archivo `marcador_*.yaml` define los parámetros propios del análisis. Edítalos según el análisis que quieras realizar:

| Parámetro | ITS | 16S | 18S |
|---|---|---|---|
| `FW_primer` / `RV_primer` | _primers_ del laboratorio | _primers_ del laboratorio | _primers_ del laboratorio |
| `cut_its` | `its1`, `its2` o `full` | (no aplica) | (no aplica) |
| `dada_ref_taxonomy` | `unite-fungi=10.0` | `silva=138` | `pr2=5.1.0` (o SILVA, ver nota) |
| `addsh` | hipótesis de especie de UNITE | (no aplica) | (no aplica) |

Puedes encontrar los catálogos de _primers_ estándar en `configuracion/primers_its.tsv`, `configuracion/primers_16s.tsv` y `configuracion/primers_18s.tsv`. Copia las secuencias que uses al `.yaml` que corresponda. Los _presets_ más comunes son:

- **ITS:** `fITS7`/`ITS4` (ITS2), `ITS1F`/`ITS2` (ITS1), `ITS3`/`ITS4` (ITS2).
- **16S:** `515F`/`806R` (V4), `341F`/`805R` (V3-V4), `27F`/`1492R` (completo).
- **18S:** `TAReuk454FWD1`/`TAReukREV3` (V4), `Euk1391F`/`EukBr` (V9).

**Nota 1:** la base `dada_ref_taxonomy` debe corresponder al marcador (UNITE solo
sirve para ITS; SILVA, GTDB o Greengenes para 16S; y PR2 o SILVA para 18S).
**Nota 2:** la SILVA de DADA2 que trae ampliseq está optimizada para Bacteria/Archaea y no trae secuencias para analizar especies del dominio Eukarya (18S). Si quieres usar SILVA en 18S, hay que usar el clasificador de QIIME2 en lugar del de DADA2 (la SILVA de QIIME2 sí trae las secuencias de 18S). En el archivo `marcador_18s.yaml`, comenta `dada_ref_taxonomy: "pr2=5.1.0"` y descomenta `qiime_ref_taxonomy: "silva=138"`.


---

## 3. Uso

```bash
# 1. Edita el archivo configuracion/parametros.sh, definiendo el entorno, marcador y demás parámetros del pipeline

# 2. Instala las dependencias necesarias (Java 17, Nextflow, etc.) y crea el ambiente, solo la primera vez
bash scripts/00_instalar_dependencias.sh

# 3. Copia tus archivos FASTQ en datos/crudos/

# 4. Genera la hoja de muestras a partir de los archivos FASTQ
bash scripts/01_generar_samplesheet.sh

# 5. (Opcional) Si estás en HPC y los nodos no tienen acceso a internet, precarga las imágenes
# 5.1. Para Docker
bash scripts/precargar_imagenes_docker_hpc.sh

# 5.2. Para Apptainer/Singularity
bash scripts/precargar_imagenes_apptainer_hpc.sh

# 6. (Opcional) Si quieres probar el ambiente, instalaciones y todo lo necesario, corre:
bash scripts/02_verificar_entorno.sh

# 7. Ejecuta el pipeline de nf-core/ampliseq
# 7.1. (Opcional) Si quieres probar el comando sin ejecutarlo
bash scripts/03_ejecutar_ampliseq.sh --dry-run

# 7.2. En local
bash scripts/03_ejecutar_ampliseq.sh

# 7.3. En el HPC, usa el wrapper
bash scripts/lanzar_hpc.sh

# 8. (Opcional) Por último, para obtener una tabla de tiempos por proceso (tareas, tiempo total y promedio, %cpu máximo y RAM pico), corre
bash scripts/04_resumen_tiempos.sh        # usa el trace de Nextflow más reciente para calcular la tabla
```
Todo el flujo es reanudable. Si se llegara a interrumpir, vuelve a correr el script 03 y Nextflow continúa donde se quedó gracias a la etiqueta `-resume`. Si quieres forzar a que el _pipeline_ ejecute alguna tarea y que no la recupere de la caché, borra la carpeta `work/`, que es donde Nextflow guarda la caché. Puedes hacerlo sin preocupaciones.

### 3.1 Prueba con datos de ejemplo

Para probar el _pipeline_ con un conjunto de datos de prueba, descarga uno de los conjuntos estándar de nf-core/test-datasets y córrelo:

```bash
# Para probar con el marcador 16S
bash scripts/descargar_datos_prueba.sh 16s   # 16S pareado (515F/806R)

# Para probar con el marcador ITS
bash scripts/descargar_datos_prueba.sh its   # ITS single-end de Illumina

# Y para probar con un conjunto pequeño para 18S
bash scripts/descargar_datos_prueba.sh 18s   # 18S pareado, un conjunto pequeño de tres muestras de Patchett et al. (2024), BioProject PRJNA947667,
# doi:10.1007/s00436-024-08136-x (18S de branquia de Salmo salar) (usa fastq-dump, necesitas instalar sra-toolkit)

# ajusta el MARCADOR y DISENO_LECTURAS según sea el caso (el script te lo recuerda)
bash scripts/01_generar_samplesheet.sh
bash scripts/03_ejecutar_ampliseq.sh
```

La primera corrida baja la base de datos de referencia para la inferencia taxonómica, que se guarda en la caché.

### 3.2 Varias corridas de secuenciación (columna `run`)

DADA2 aprende el perfil de error de cada corrida de secuenciación por separado, y mezclar corridas en un mismo modelo degrada los ASVs. Si tienes archivo FASTQ de dos o más corridas de secuenciación diferentes, esta función te servirá. La hoja de muestras lleva una columna `run` para indicar la corrida y el script 01 la llena sola. Pon los FASTQ de cada corrida en su propia subcarpeta dentro de `datos/crudos/` y `run` tomará el nombre de la subcarpeta.

```
datos/crudos/
├── corrida1/   ← run = corrida1
│   ├── M1_R1.fastq.gz
│   └── M1_R2.fastq.gz
└── corrida2/   ← run = corrida2
    ├── M2_R1.fastq.gz
    └── M2_R2.fastq.gz
```

Si dejas los FASTQ sueltos en `datos/crudos/`, todos quedan en la corrida `1`. También puedes editar la columna `run` a mano después de generar la hoja. Si usas hoja de muestras (`USAR_SAMPLESHEET="si"`), entonces no uses `--multiple_sequencing_runs`, esa bandera es solo para la entrada por carpeta.

---


## 4. Resultados principales

Dentro de `resultados/<PROYECTO>/` encontrarás (entre otros):

| Carpeta | Contenido |
|---|---|
| `dada2/` | Tabla de ASVs, secuencias representativas y estadísticas |
| `cutadapt/` | Reporte de eliminación de _primers_ |
| `itsx/` | Secuencias ITS recortadas (solo en ITS) |
| `qiime2/` | Diversidad alfa/beta y abundancias relativas (si hay metadatos) |
| `multiqc/` | Reporte de calidad concatenado (abrir el `.html`) |
| `summary_report/` | Resumen del análisis (abrir el `.html`) |
| `pipeline_info/` | Versiones, tiempos y trazabilidad de la corrida |



---

## 5. _Debugging_

- **Docker no responde (local):** abre Docker Desktop y activa la integración
  con tu distro (Settings → Resources → WSL integration). Como alternativa, en
  `configuracion/parametros.sh` cambia `MOTOR` a `apptainer` o `conda`.
- **Las tareas fallan por Docker (HPC):** asegúrate de que se fijen a los nodos
  con Docker. En `configuracion/recursos_hpc.config`, `--nodelist=nodo27,nodo28`
  limita las tareas a esos nodos, ajústalo si Docker está en otros nodos de tu clúster.
- **El _job_ maestro no inicia (HPC):** revisa que los nodos de `NODOS_MAESTRO`
  (parametros.sh), tu cuenta y tu partición existan, y que `conda` esté disponible
  en ellos (carga el módulo o ajusta la ruta en `scripts/lanzar_hpc.slurm`). Si
  `lanzar_hpc.sh` no encuentra un nodo vacío, entonces manda a la cola el _job_ maestro en el nodo con más CPUs libres.
- **Se queda sin memoria / se congela la laptop:** baja `queueSize` (recomiendo usar 2)
  en `configuracion/recursos_local.config`.
- **Las tareas no entran a la cola (HPC):** revisa la cuenta y la partición en
  `configuracion/recursos_hpc.config`.
- **Muchas lecturas se descartan en el filtrado:** en `parametros.sh` agrega
  `EXTRA_PARAMS="--truncq 4"` y ve probando hasta encontrar un valor que se ajuste a tus secuencias.
- **Una muestra pierde todas sus lecturas y el flujo falla:** activa `IGNORAR_RECORTE_FALLIDO="si"`.

---

## 6. Cómo citar

### 6.1 Este repositorio

Este _pipeline_ es una contribución del Laboratorio de Metagenómica, del CICESE. Si este repo te ayudó, te agradecería una estrella ⭐ y una cita:

Castañeda-Martínez, R. (2026). *metabarcoding ampliseq: uso de nf-core/ampliseq para realizar metabarcoding* (v0.2.0) [Software]. Zenodo. https://doi.org/10.5281/zenodo.20711275

En BibTeX:

```bibtex
@software{castaneda_martinez_metabarcoding_ampliseq_2026,
  author    = {Castañeda-Martínez, Rubén},
  title     = {metabarcoding ampliseq: uso de nf-core/ampliseq para realizar metabarcoding},
  year      = {2026},
  version   = {v0.2.0},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.20711275},
  url       = {https://doi.org/10.5281/zenodo.20711275}
}
```

También puedes usar el botón ***"Cite this repository"*** del repo.

### 6.2 El _pipeline_ y sus herramientas

Si usas este flujo, hay que citar a nf-core/ampliseq y las herramientas y bases de datos que ejecuta (DADA2, cutadapt, QIIME2, ITSx en ITS, y la base de datos correspondiente). nf-core genera la lista completa de citas, con versiones y DOIs, en `resultados/<PROYECTO>/pipeline_info/`. Las principales son:

- nf-core/ampliseq: Straub et al. (2020) *Front Microbiol* 11:550420. https://doi.org/10.3389/fmicb.2020.550420
- nf-core: Ewels et al. (2020) *Nat Biotechnol* 38:276–278. https://doi.org/10.1038/s41587-020-0439-x
- UNITE Community (ITS): https://unite.ut.ee
- SILVA (16S/18S): Quast et al. (2013) *Nucleic Acids Res* 41:D590–D596. https://www.arb-silva.de
- PR2 (18S): Guillou et al. (2013) *Nucleic Acids Res* 41:D597–D604. https://pr2-database.org
