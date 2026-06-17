# _Metabarcoding_ (ITS de hongos / 16S de procariotas / 18S de eucariotas) con nf-core/ampliseq

[![shellcheck](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/shellcheck.yml) [![nextflow-config](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/nextflow-config.yml/badge.svg)](https://github.com/ruben1294/metabarcoding_ampliseq/actions/workflows/nextflow-config.yml) [![DOI](https://zenodo.org/badge/1266027343.svg)](https://doi.org/10.5281/zenodo.20711275)

Flujo de trabajo para hacer un análisis de _metabarcoding_ (también conocido como análisis de amplicones) a partir de secuencias amplificadas por PCR y secuenciadas con la plataforma Illumina, con tres
marcadores genéticos posibles: la región ITS (*Internal Transcribed Spacer*) de hongos, el gen 16S rDNA de procariotas o el gen 18S rDNA de eucariotas.

Usa [nf-core/ampliseq](https://nf-co.re/ampliseq) (v2.17.0), que ejecuta:
control de calidad (FastQC), eliminación de *primers* (cutadapt), inferencia de
_Amplicon Sequence Variants_ (ASVs) (DADA2), recorte de la región ITS con ITSx (solo en
ITS), inferencia taxonómica y
análisis de diversidad (QIIME2), con reportes finales (MultiQC y reporte resumen).

El objetivo de este _pipeline_ es llamar a nf-core/ampliseq y resolver la instalación de dependencias y la definición de parámetros para que puedas correr tu análisis de manera fluida y sencilla, sin preocuparte por instalar (casi) nada.

---

## 1. Estructura del proyecto

```
metabarcoding_ampliseq/
├── README.md                          ← este archivo
├── configuracion/
│   ├── parametros.sh                  ← Edita aquí los parámetros para el flujo de trabajo
│   ├── recursos_local.config          ← definición de recursos para correr en local
│   ├── recursos_hpc.config            ← definición de recursos, cola y nodos con Docker del HPC (con SLURM)
│   ├── marcador_its.yaml              ← parámetros del análisis de ITS (hongos)
│   ├── marcador_16s.yaml              ← parámetros del análisis de 16S (procariotas)
│   ├── marcador_18s.yaml              ← parámetros del análisis de 18S (eucariotas)
│   ├── primers_its.tsv                ← catálogo de primers estándar para ITS
│   ├── primers_16s.tsv                ← catálogo de primers estándar 16S
│   ├── primers_18s.tsv                ← catálogo de primers estándar 18S
│   └── samplesheet.tsv                ← (lo genera el script 01)
├── scripts/
│   ├── 00_instalar_dependencias.sh    ← verifica e instala todo lo que falte
│   ├── 01_generar_samplesheet.sh      ← crea la hoja de muestras desde los FASTQ
│   ├── 02_verificar_entorno.sh        ← verifica que todo esté listo
│   ├── 03_ejecutar_ampliseq.sh        ← corre el análisis
│   ├── 04_resumen_tiempos.sh          ← crea la tabla de tiempos por proceso de la corrida
│   ├── lanzar_hpc.sh                  ← lanza el job maestro en el HPC (wrapper)
│   ├── lanzar_hpc.slurm               ← script SLURM del job maestro
│   ├── precargar_imagenes_docker_hpc.sh ← precarga imágenes Docker en nodo27/28 (HPC)
│   ├── precargar_imagenes_apptainer_hpc.sh ← precarga imágenes .sif y bases en referencias/ (apptainer/singularity)
│   ├── descargar_datos_prueba.sh      ← baja un conjunto pequeño y estándar para probar
│   └── lib/                           ← funciones comunes (registro, entorno y marcador)
├── datos/crudos/                       ← ⬅️ pon aquí tus FASTQ (.fastq.gz)
├── metadatos/
│   └── metadatos.tsv.ejemplo           ← plantilla de metadatos para QIIME2
├── referencias/                        ← caché de apptainer/singularity (ignorada en git)
│   ├── imagenes/                       ← imágenes .sif de los contenedores
│   └── bases/                          ← bases de datos taxonómicas que baja el pipeline
├── resultados/<PROYECTO>/              ← resultados, una subcarpeta por proyecto
└── logs/<PROYECTO>/                    ← logs de cada corrida, también por proyecto
```

---

## 2. Definición de entorno y marcador

Al iniciar, los _scripts_ te preguntan dónde correrás el flujo y qué marcador analizarás, si no las has definido ya. Para no responder cada vez que corres un _script_, defínelas en `configuracion/parametros.sh`. En un HPC es obligatorio definirlas si lanzas el _pipeline_ sin terminal interactiva.

### a) Entorno donde correrá el _pipeline_

- **`local`**: tu computadora. Usa Docker y los núcleos de la computadora, con los
  límites de recursos definidos en `configuracion/recursos_local.config`. Probado en una laptop con WSL y Docker Desktop previamente conectado. La arquitectura con esta opción es más sencilla.
- **`hpc`**: un clúster con SLURM. Manda cada tarea a la cola y la corre con
  Docker (o el motor elegido), usando los límites definidos en `configuracion/recursos_hpc.config`.

En el HPC de OMICA (CICESE) el motor es Docker, pero actualmente este solo está instalado en los nodos: nodo5, nodo27 y nodo28. La arquitectura elegida es que el _job_ maestro corre en uno de esos tres nodos y nodo27 y nodo28 se usan para lanzar los _jobs_ hijos que realizan el análisis del _pipeline_. El  _job_ maestro es un orquestador que pide pocos recursos, entonces puede compartir nodo27/nodo28 con las tareas. Todo esto ya viene configurado en `recursos_hpc.config`, en `scripts/lanzar_hpc.slurm` y en `NODOS_MAESTRO` (parametros.sh). Ajusta tu cuenta, partición o los nodos si tu clúster es diferente.

Para correr el _pipeline_ en el HPC, lanza el _job_ maestro con el _wrapper_, que elige el primer nodo permitido con espacio disponible (tiene que permanecer vivo durante todo el análisis):

```bash
bash scripts/lanzar_hpc.sh
```

También puedes enviarlo directo con `sbatch scripts/lanzar_hpc.slurm` (el _job_ maestro se manda a nodo5), o correr `bash scripts/03_ejecutar_ampliseq.sh` a mano dentro de `tmux` o `screen`, aunque te recomiendo usar el _wrapper_.

#### HPC de OMICA

En OMICA el internet general está bloqueado, pero los nodos con Docker (nodo5/nodo27/nodo28) sí pueden conectarse con el registro de contenedores (`quay.io`) usados en el _pipeline_. El *job* maestro corre en modo *offline* para el *pipeline* (`NXF_OFFLINE=true`, que se define automáticamente en `ENTORNO=hpc` y usa la copia cacheada), y las imágenes de los contenedores a usar se jalan al correr. Para correr el _pipeline_ allí, los pasos son:

1. ***Pipeline*** (lo hace el script 00, en el nodo interactivo con internet): `NXF_OFFLINE=false nextflow pull nf-core/ampliseq -r 2.17.0`.
2. **Imágenes de contenedor** (`MOTOR="docker"`, el predeterminado): recomiendo precargar las imágenes una vez en cada nodo con: `bash scripts/precargar_imagenes_docker_hpc.sh`. Ese paso también deja cacheados los *plugins* de Nextflow que el *job* maestro usará en modo *offline*.
3. **Bases de datos taxonómicos**: si los nodos no pueden conectarse con los servidores de las bases de datos (UNITE, SILVA, PR2, etc.), descárgalas en `DIR_BASES_HPC` (LUSTRE) y escribe la ruta en el YAML del marcador a los archivos locales (`dada_ref_tax_custom`, etc.). Cada `marcador_*.yaml` trae ya la estructura comentada y el comando para sacar la URL o el archivo exacto del *pipeline*, todo listo solo para que definas las rutas reales.

Si en vez de Docker usas **apptainer** o **singularity**, no necesitas el paso 3 a mano: precarga las imágenes y las bases de una sola vez en el nodo interactivo con `bash scripts/precargar_imagenes_apptainer_hpc.sh`, que las deja ordenadas en `referencias/` (`imagenes/` y `bases/`). El *job* maestro las reutiliza *offline* desde ahí, sin volver a bajarlas. Si los nodos de cómputo no ven la carpeta del proyecto o no puedes escribir en ella, apunta `DIR_REFERENCIAS` (parametros.sh) a una ruta tuya en LUSTRE.

### b) Marcador genético a analizar

- **`its`**: hongos. Región ITS, base de datos predeterminada UNITE. Parámetros en
  `configuracion/marcador_its.yaml`.
- **`16s`**: procariotas. Gen 16S rDNA, base de datos predeterminada SILVA. Parámetros en
  `configuracion/marcador_16s.yaml`.
- **`18s`**: eucariotas. Gen 18S rDNA, base de datos predeterminada PR2.
  Parámetros en `configuracion/marcador_18s.yaml`.

Cada marcador trae sus _primers_ y su base de datos en un archivo `.yaml` que se pasa a Nextflow con `-params-file`. Ahí es donde debes editar los parámetros del análisis.

---

## 3. Uso

```bash
# 1) Instala las dependencias necesarias (Java 17, Nextflow, etc.), solo la primera vez
bash scripts/00_instalar_dependencias.sh

# (copia tus archivos FASTQ en datos/crudos/)

# 2) Genera la hoja de muestras a partir de los FASTQ
bash scripts/01_generar_samplesheet.sh

# 3) (Opcional) Si quieres probar el ambiente, instalaciones y todo lo necesario, corre:
bash scripts/02_verificar_entorno.sh

# 4.1) En local, corre el análisis completo
bash scripts/03_ejecutar_ampliseq.sh

# 4.2) En el HPC, usa el wrapper
bash scripts/lanzar_hpc.sh

```

Para revisar el comando sin ejecutarlo:
```bash
bash scripts/03_ejecutar_ampliseq.sh --dry-run
```

Por último, para obtener una tabla de tiempos por proceso (tareas, tiempo total y promedio, %cpu máximo y RAM pico), corre:

```bash
bash scripts/04_resumen_tiempos.sh        # usa el trace de Nextflow más reciente para calcular la tabla
```

### 3.1 Prueba con datos de ejemplo

Para probar el flujo con un conjunto de datos de prueba, descarga uno de los conjuntos estándar de nf-core/test-datasets y córrelo:

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

---

## 4. Parámetros del marcador

Cada archivo `marcador_*.yaml` define los parámetros propios del análisis. Edítalos según el análisis que quieras realizar:

| Parámetro | ITS | 16S | 18S |
|---|---|---|---|
| `FW_primer` / `RV_primer` | _primers_ del laboratorio | _primers_ del laboratorio | _primers_ del laboratorio |
| `cut_its` | `its1`, `its2` o `full` | (no aplica) | (no aplica) |
| `dada_ref_taxonomy` | `unite-fungi=10.0` | `silva=138` | `pr2=5.1.0` (o SILVA, ver nota) |
| `addsh` | hipótesis de especie de UNITE | (no aplica) | (no aplica) |

Puedes encontrar los catálogos de _primers_ estándar en `configuracion/primers_its.tsv`, `configuracion/primers_16s.tsv` y `configuracion/primers_18s.tsv`. Copia las secuencias que uses al `.yaml`
que corresponda. Los _presets_ más comunes son:

- **ITS:** `fITS7`/`ITS4` (ITS2), `ITS1F`/`ITS2` (ITS1), `ITS3`/`ITS4` (ITS2).
- **16S:** `515F`/`806R` (V4), `341F`/`805R` (V3-V4), `27F`/`1492R` (completo).
- **18S:** `TAReuk454FWD1`/`TAReukREV3` (V4), `Euk1391F`/`EukBr` (V9).

**Nota 1:** la base `dada_ref_taxonomy` debe corresponder al marcador (UNITE solo
sirve para ITS; SILVA, GTDB o Greengenes para 16S; y PR2 o SILVA para 18S).
**Nota 2:** la SILVA de DADA2 que trae ampliseq está optimizada para
Bacteria/Archaea y no trae secuencias aptas para analizar especies del dominio Eukarya. Si quieres usar SILVA en 18S, hay que usar el clasificador de QIIME2: en
`marcador_18s.yaml`, comenta `dada_ref_taxonomy: "pr2=5.1.0"` y descomenta
`qiime_ref_taxonomy: "silva=138"` (la SILVA de QIIME2 sí trae las secuencias de 18S).

---

Todo el flujo es reanudable. Si se llegara a interrumpir, vuelve a correr el script 03 y Nextflow continúa donde se quedó gracias a la etiqueta `-resume`.

---

## 5. Resultados principales

Dentro de `resultados/<PROYECTO>/` encontrarás (entre otros):

| Carpeta | Contenido |
|---|---|
| `dada2/` | Tabla de ASVs, secuencias representativas y estadísticas |
| `cutadapt/` | Reporte de eliminación de _primers_ |
| `itsx/` | Secuencias ITS recortadas (solo en ITS) |
| `dada2/<bd>/` | Taxonomía inferida (UNITE o SILVA) |
| `qiime2/` | Diversidad alfa/beta y abundancias relativas (si hay metadatos) |
| `multiqc/` | Reporte de calidad concatenado (abrir el `.html`) |
| `summary_report/` | Resumen del análisis (abrir el `.html`) |
| `pipeline_info/` | Versiones, tiempos y trazabilidad de la corrida |



---

## 6. _Debugging_

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
- **Se queda sin memoria / se congela la laptop:** baja `queueSize` (de 4 a 2)
  en `configuracion/recursos_local.config`.
- **Las tareas no entran a la cola (HPC):** revisa la cuenta y la partición en
  `configuracion/recursos_hpc.config`.
- **Muchas lecturas se descartan en el filtrado:** en `parametros.sh` agrega
  `EXTRA_PARAMS="--truncq 4"` y ve probando hasta encontrar un valor que se ajuste a tus secuencias.
- **Una muestra pierde todas sus lecturas y aborta:** agrega
  `EXTRA_PARAMS="--ignore_failed_trimming"`.

---

## 7. Cómo citar

### 7.1 Este repositorio

Si este repo te ayudó, te agradecería una estrellita ⭐ y una cita:

Castañeda-Martínez, R. (2026). *metabarcoding ampliseq: uso de nf-core/ampliseq para realizar metabarcoding* (v0.1.1) [Software]. Zenodo. https://doi.org/10.5281/zenodo.20711275

En BibTeX:

```bibtex
@software{castaneda_martinez_metabarcoding_ampliseq_2026,
  author    = {Castañeda-Martínez, Rubén},
  title     = {metabarcoding ampliseq: uso de nf-core/ampliseq para realizar metabarcoding},
  year      = {2026},
  version   = {v0.1.1},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.20711275},
  url       = {https://doi.org/10.5281/zenodo.20711275}
}
```

También puedes usar el botón **"Cite this repository"** del repo (lee el `CITATION.cff`).

### 7.2 El _pipeline_ y sus herramientas

Si usas este flujo, hay que citar a nf-core/ampliseq y las herramientas y bases de datos que ejecuta (DADA2, cutadapt, QIIME2, ITSx en ITS, y la base de datos correspondiente). nf-core genera la lista completa de citas, con versiones y DOIs, en `resultados/<PROYECTO>/pipeline_info/`. Las principales son:

- nf-core/ampliseq: Straub et al. (2020) *Front Microbiol* 11:550420. https://doi.org/10.3389/fmicb.2020.550420
- nf-core: Ewels et al. (2020) *Nat Biotechnol* 38:276–278. https://doi.org/10.1038/s41587-020-0439-x
- UNITE Community (ITS): https://unite.ut.ee
- SILVA (16S/18S): Quast et al. (2013) *Nucleic Acids Res* 41:D590–D596. https://www.arb-silva.de
- PR2 (18S): Guillou et al. (2013) *Nucleic Acids Res* 41:D597–D604. https://pr2-database.org
