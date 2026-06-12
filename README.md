# Análisis de amplicones (ITS de hongos / 16S de procariotas / 18S de eucariotas) con nf-core/ampliseq

Flujo para analizar amplicones a partir de secuenciación Illumina, con tres
marcadores posibles: la región ITS (*Internal Transcribed Spacer*) de hongos, el
gen 16S rDNA de procariotas o el gen 18S rDNA de eucariotas.

Usa [nf-core/ampliseq](https://nf-co.re/ampliseq) (v2.17.0), que ejecuta:
control de calidad (FastQC), eliminación de *primers* (cutadapt), inferencia de
_Amplicon Sequence Variants_ (ASVs) (DADA2), recorte de la región ITS con ITSx (solo en
ITS), inferencia taxonómica (UNITE para ITS, SILVA para 16S, PR2 para 18S) y
análisis de diversidad (QIIME2), con reportes finales (MultiQC y reporte resumen).

Antes de correr el _pipeline_, hay dos decisiones importantes y cada una tiene su propio archivo:

| Decisión | Opciones | Define | Archivo |
|---|---|---|---|
| **Entorno** | `local` / `hpc` | recursos y ejecutor | `recursos_<entorno>.config` (vía `-c`) |
| **Marcador** | `its` / `16s` / `18s` | primers y base de datos | `marcador_<marcador>.yaml` (vía `-params-file`) |

---

## 1. Estructura del proyecto

```
qiime2_ampliseq/
├── README.md                          ← este archivo
├── configuracion/
│   ├── parametros.sh                  ← Edita aquí las decisiones y los datos de entrada
│   ├── recursos_local.config          ← recursos para correr en local
│   ├── recursos_hpc.config            ← recursos, cola y nodos con Docker del HPC (SLURM)
│   ├── marcador_its.yaml              ← parámetros del análisis de ITS (hongos)
│   ├── marcador_16s.yaml              ← parámetros del análisis de 16S (procariotas)
│   ├── marcador_18s.yaml              ← parámetros del análisis de 18S (microeucariotas)
│   ├── primers_ITS.tsv                ← catálogo de primers ITS estándar
│   ├── primers_16S.tsv                ← catálogo de primers 16S estándar
│   ├── primers_18S.tsv                ← catálogo de primers 18S estándar
│   └── samplesheet.tsv                ← (lo genera el script 01)
├── scripts/
│   ├── 00_instalar_dependencias.sh    ← verifica e instala todo lo que falte
│   ├── 01_generar_samplesheet.sh      ← crea la hoja de muestras desde los FASTQ
│   ├── 02_verificar_entorno.sh        ← diagnóstico: verifica que todo esté listo
│   ├── 03_ejecutar_ampliseq.sh        ← ejecuta el análisis
│   ├── 04_resumen_tiempos.sh          ← arma la tabla de tiempos por proceso de la corrida
│   ├── lanzar_hpc.slurm               ← job maestro para lanzar en el HPC
│   ├── descargar_datos_prueba.sh      ← baja un set pequeño y estándar para probar
│   └── lib/                           ← funciones comunes (registro, entorno y marcador)
├── datos/crudos/                       ← ⬅️ pon aquí tus FASTQ (.fastq.gz)
├── metadatos/
│   └── metadatos.tsv.ejemplo           ← plantilla de metadatos (QIIME2)
├── resultados/<PROYECTO>/              ← resultados, una subcarpeta por proyecto (se crean solas)
└── logs/<PROYECTO>/                    ← logs de cada corrida, también por proyecto (se crean solas)
```

---

## 2. Decisiones del flujo

Al iniciar, los scripts te preguntan dónde correrás el flujo y qué marcador analizarás (si no las has fijado antes). Para no responder cada vez, definelas en `configuracion/parametros.sh`; en un HPC es
obligatorio definirlas si lanzas el _pipeline_ sin terminal interactiva.

### a) Entorno: `local` o `hpc`

- **`local`** → tu computadora. Usa Docker y los núcleos de la máquina, con los
  topes de recursos de `configuracion/recursos_local.config`.
- **`hpc`** → un clúster con SLURM. Manda cada tarea a la cola y la corre con
  Docker, con `configuracion/recursos_hpc.config`.

En el HPC de OMICA (CICESE) el motor es Docker, pero actualmente este solo está instalado en los siguientes nodos: nodo5, nodo27 y nodo28. La arquitectura elegida es que el _job_ maestro corre en el nodo5, y nodo27 y nodo28 se usan para lanzar los _jobs_ hijos que realizan el análisis del _pipeline_. Todo esto ya viene configurado en `recursos_hpc.config` y en `scripts/lanzar_hpc.slurm`. Ajusta tu cuenta, partición o los nodos si tu clúster es distinto.

Para correr el _pipeline_ en el HPC, lanza el _job_ maestro (tiene que permanecer vivo durante todo el análisis):

```bash
sbatch scripts/lanzar_hpc.slurm
```

Como alternativa, corre `bash scripts/03_ejecutar_ampliseq.sh` a mano desde nodo5 dentro de `tmux` o `screen`.

### b) Marcador: `its`, `16s` o `18s`

- **`its`** → hongos. Región ITS, base de datos predeterminada UNITE. Parámetros en
  `configuracion/marcador_its.yaml`.
- **`16s`** → procariotas. Gen 16S rDNA, base de datos predeterminada SILVA. Parámetros en
  `configuracion/marcador_16s.yaml`.
- **`18s`** → eucariotas. Gen 18S rDNA, base de datos predeterminada PR2.
  Parámetros en `configuracion/marcador_18s.yaml`.

Cada marcador trae sus _primers_ y su base de datos en un archivo `.yaml` que se pasa a Nextflow con `-params-file`. Ahí es donde debes editar los parámetros del análisis.

---

## 3. Uso

```bash
# 1) Instala dependencias (Java 17, Nextflow, etcétera). Solo la primera vez.
bash scripts/00_instalar_dependencias.sh

# (copia tus archivos FASTQ en datos/crudos/)

# 2) Genera la hoja de muestras a partir de los FASTQ
bash scripts/01_generar_samplesheet.sh

# 3) Ejecuta el análisis completo
bash scripts/03_ejecutar_ampliseq.sh
```

> **En el HPC:** define `ENTORNO="hpc"` en `configuracion/parametros.sh`, corre los
> pasos 1 y 2 en el clúster y, en vez del paso 3, lanza el _job_ maestro:
> `sbatch scripts/lanzar_hpc.slurm` (corre en nodo5 y usa Docker en nodo27/nodo28).

Para revisar el comando sin ejecutarlo:
```bash
bash scripts/03_ejecutar_ampliseq.sh --dry-run
```

Para diagnosticar el entorno en cualquier momento:
```bash
bash scripts/02_verificar_entorno.sh
```

### Probar con datos de ejemplo

Para validar el flujo sin tus datos, baja un conjunto pequeño y estándar
(nf-core/test-datasets) y córrelo de punta a punta:

```bash
bash scripts/descargar_datos_prueba.sh 16s   # 16S pareado (515F/806R)
# o:  bash scripts/descargar_datos_prueba.sh its   # ITS single-end de Illumina

# ajusta el MARCADOR y DISENO_LECTURAS según sea el caso (el script te lo recuerda)
bash scripts/01_generar_samplesheet.sh
bash scripts/03_ejecutar_ampliseq.sh
```

El entorno (local o HPC) es independiente, el mismo dato sirve para ambos. La primera corrida baja la base de datos de referencia para la inferencia taxonómica (que se guarda en caché).

---

## 4. Ajustar los parámetros del marcador

Cada archivo `marcador_*.yaml` define los parámetros propios del análisis. Edítalos según el análisis que quieras realizar:

| Parámetro | ITS | 16S | 18S |
|---|---|---|---|
| `FW_primer` / `RV_primer` | _primers_ del laboratorio | _primers_ del laboratorio | _primers_ del laboratorio |
| `cut_its` | `its1`, `its2` o `full` | (no aplica) | (no aplica) |
| `dada_ref_taxonomy` | `unite-fungi=10.0` | `silva=138` | `pr2=5.1.0` (o SILVA, ver nota) |
| `addsh` | hipótesis de especie de UNITE | (no aplica) | (no aplica) |

Puedes encontrar los catálogos de _primers_ estándar en `configuracion/primers_ITS.tsv`, `configuracion/primers_16S.tsv` y `configuracion/primers_18S.tsv`. Copia las secuencias que uses al `.yaml`
que corresponda. Los _presets_ más comunes son:

- **ITS:** `fITS7`/`ITS4` (ITS2), `ITS1F`/`ITS2` (ITS1), `ITS3`/`ITS4` (ITS2).
- **16S:** `515F`/`806R` (V4), `341F`/`805R` (V3-V4), `27F`/`1492R` (completo).
- **18S:** `TAReuk454FWD1`/`TAReukREV3` (V4), `Euk1391F`/`EukBr` (V9).

> **Nota:** la base `dada_ref_taxonomy` debe corresponder al marcador (UNITE solo
> sirve para ITS; SILVA, GTDB o Greengenes para 16S; y PR2 o SILVA para 18S).
>
> **18S con SILVA:** la SILVA de DADA2 que trae ampliseq está optimizada para
> Bacteria/Archaea y su documentación la marca no apta para eucariotas. Para
> usar SILVA en 18S hay que usar el clasificador de QIIME2: en
> `marcador_18s.yaml`, comenta `dada_ref_taxonomy: "pr2=5.1.0"` y descomenta
> `qiime_ref_taxonomy: "silva=138"` (la SILVA de QIIME2 es la combinada 16S/18S).

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
| `dada2/<bd>/` | Taxonomía asignada (UNITE o SILVA) |
| `qiime2/` | Diversidad alfa/beta y abundancias relativas (si hay metadatos) |
| `multiqc/` | Reporte de calidad agregado (abrir el `.html`) |
| `summary_report/` | Reporte resumen del análisis (abrir el `.html`) |
| `pipeline_info/` | Versiones, tiempos y trazabilidad de la corrida |

Para una tabla de tiempos por proceso (tareas, tiempo total y promedio, %cpu máximo
y RAM pico) a partir del `execution_trace` que Nextflow pone en `pipeline_info/`, corre:

```bash
bash scripts/04_resumen_tiempos.sh        # usa el trace más reciente
```

---

## 6. _Debugging_

- **Docker no responde (local)** → abre Docker Desktop y activa la integración
  con tu distro (Settings → Resources → WSL integration). Como alternativa, en
  `configuracion/parametros.sh` cambia `MOTOR` a `apptainer` o `conda`.
- **Las tareas fallan por Docker (HPC)** → asegúrate de que se fijen a los nodos
  con Docker. En `configuracion/recursos_hpc.config`, `--nodelist=nodo27,nodo28`
  limita las tareas a esos nodos, ajústalo si Docker está en otros nodos de tu clúster.
- **El _job_ maestro no inicia (HPC)** → revisa que `--nodelist=nodo5`, tu cuenta y
  tu partición existan en `scripts/lanzar_hpc.slurm`, y que `conda` esté disponible
  en nodo5 (carga el módulo o ajusta la ruta en el script).
- **Se queda sin memoria / se congela la laptop** → baja `queueSize` (de 4 a 2)
  en `configuracion/recursos_local.config`.
- **Las tareas no entran a la cola (HPC)** → revisa la cuenta y la partición en
  `configuracion/recursos_hpc.config`.
- **Muchas lecturas se descartan en el filtrado** → en `parametros.sh` agrega
  `EXTRA_PARAMS="--truncq 4"` (recomendado en ITS por su longitud variable).
- **Una muestra pierde todas sus lecturas y aborta** → agrega
  `EXTRA_PARAMS="--ignore_failed_trimming"`.

---

## 7. Cómo citar

Si usas este _pipeline_, cita a nf-core/ampliseq, DADA2, cutadapt, QIIME2, ITSx (en ITS) y la base de datos correspondiente. nf-core genera la lista de citas en `resultados/<PROYECTO>/pipeline_info/`.

- nf-core: Ewels et al. (2020) *Nat Biotechnol*. https://nf-co.re/ampliseq
- UNITE Community: https://unite.ut.ee
- SILVA: Quast et al. (2013) *Nucleic Acids Res*. https://www.arb-silva.de
- PR2: Guillou et al. (2013) *Nucleic Acids Res*. https://pr2-database.org

Si este repo te ayudó, te agradecería una estrellita ⭐ y una cita:

Castañeda-Martínez, R. (2026). QIIME2 ampliseq: uso de nf-core para realizar un análisis de amplicones. [Software]. GitHub. https://github.com/ruben1294/qiime2_ampliseq
