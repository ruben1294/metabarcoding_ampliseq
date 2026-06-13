#!/usr/bin/env bash
# =============================================================================
#  01_generar_samplesheet.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Crea automáticamente la "hoja de muestras" (samplesheet) que nf-core/ampliseq
#  necesita, leyendo los archivos FASTQ de la carpeta CARPETA_FASTQ.
#
#  Formato generado (TSV, según la especificación de nf-core/ampliseq):
#     sample  <tab>  fastq_1  <tab>  fastq_2
#
#  Reconoce los nombres típicos de Illumina, p. ej.:
#     MUESTRA_S1_L001_R1_001.fastq.gz  /  MUESTRA_S1_L001_R2_001.fastq.gz
#     MUESTRA_R1.fastq.gz              /  MUESTRA_R2.fastq.gz
#     MUESTRA_1.fastq.gz               /  MUESTRA_2.fastq.gz
#
#  Importante: revisa el archivo generado y corrige los nombres de las muestras si
#  hace falta. Deben empezar con letra y contener solo letras, números o "_".
#
#  Uso:   bash scripts/01_generar_samplesheet.sh
# =============================================================================
set -euo pipefail

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR_PROYECTO"
source "configuracion/parametros.sh"

# Registro (logging) común: INFO/WARN→stdout(.out), ERROR→stderr(.err)
source "scripts/lib/registro.sh"
iniciar_registro "01_generar_samplesheet"
activar_trap_errores

cabecera_registro "GENERAR HOJA DE MUESTRAS. Proyecto: $PROYECTO"

log_info "Buscando FASTQ en: $CARPETA_FASTQ"
[ -d "$CARPETA_FASTQ" ] || { log_error "no existe la carpeta $CARPETA_FASTQ"; exit 1; }

mkdir -p "$(dirname "$SAMPLESHEET")"

# Función: deriva un nombre de muestra limpio a partir del nombre de archivo R1.
derivar_nombre() {
    local base="$1"
    base="${base%.fastq.gz}"; base="${base%.fq.gz}"
    # Quitar el indicador de lectura (uno solo) y luego los sufijos de Illumina.
    # La alternación evita que un nombre que acaba en _1 (p. ej. una réplica)
    # pierda ese sufijo después de haber quitado _R1.
    base="$(printf '%s' "$base" \
        | sed -E 's/_(R1_001|R1|1)$//' \
        | sed -E 's/_L[0-9]{3}$//' \
        | sed -E 's/_S[0-9]+$//')"
    # Sanear: reemplazar caracteres no válidos por "_"
    base="$(printf '%s' "$base" | tr -c 'A-Za-z0-9_' '_')"
    # Debe empezar con letra; si no, anteponer "S_"
    [[ "$base" =~ ^[A-Za-z] ]] || base="S_${base}"
    printf '%s' "$base"
}

# Encabezado del TSV
if [ "$DISENO_LECTURAS" = "single" ]; then
    printf 'sample\tfastq_1\n' > "$SAMPLESHEET"
else
    printf 'sample\tfastq_1\tfastq_2\n' > "$SAMPLESHEET"
fi

# Reunir todos los R1 (varios patrones de nombre posibles)
mapfile -t R1S < <(find "$CARPETA_FASTQ" -maxdepth 1 -type f \
    \( -name "*_R1_001.fastq.gz" -o -name "*_R1.fastq.gz" -o -name "*_1.fastq.gz" \) \
    | sort)

if [ "${#R1S[@]}" -eq 0 ]; then
    log_error "no se encontraron archivos R1 (*_R1_001.fastq.gz, *_R1.fastq.gz o *_1.fastq.gz)"
    log_error "  Revisa que los FASTQ estén en $CARPETA_FASTQ y terminen en .fastq.gz"
    exit 1
fi

N=0
for r1 in "${R1S[@]}"; do
    nombre="$(derivar_nombre "$(basename "$r1")")"
    r1_abs="$(readlink -f "$r1")"

    if [ "$DISENO_LECTURAS" = "single" ]; then
        printf '%s\t%s\n' "$nombre" "$r1_abs" >> "$SAMPLESHEET"
        N=$((N+1))
        continue
    fi

    # Derivar el R2 correspondiente. El indicador de lectura va al final del
    # nombre, antes de la extensión; lo reemplazamos solo ahí (no en la ruta ni
    # en el nombre de la muestra) probando los tres estilos.
    dir="$(dirname "$r1")"; nom="$(basename "$r1")"
    cuerpo="$nom"; ext=""
    case "$nom" in
        *.fastq.gz) ext=".fastq.gz"; cuerpo="${nom%.fastq.gz}" ;;
        *.fq.gz)    ext=".fq.gz";    cuerpo="${nom%.fq.gz}" ;;
    esac
    r2=""
    for par in "_R1_001:_R2_001" "_R1:_R2" "_1:_2"; do
        a="${par%%:*}"; b="${par##*:}"
        if [ "${cuerpo%"$a"}" != "$cuerpo" ]; then
            cand="$dir/${cuerpo%"$a"}${b}${ext}"
            if [ -f "$cand" ]; then r2="$cand"; break; fi
        fi
    done

    if [ -z "$r2" ]; then
        log_warn "No encontré R2 para: $(basename "$r1")  → muestra OMITIDA"
        continue
    fi
    printf '%s\t%s\t%s\n' "$nombre" "$r1_abs" "$(readlink -f "$r2")" >> "$SAMPLESHEET"
    N=$((N+1))
done

# Nombres de muestra repetidos: ampliseq abortaría a mitad de corrida, así que lo
# atajamos aquí. Pasa si dos FASTQ distintos reducen al mismo nombre.
dups="$(cut -f1 "$SAMPLESHEET" | tail -n +2 | sort | uniq -d)"
if [ -n "$dups" ]; then
    log_error "Nombres de muestra repetidos en $SAMPLESHEET:"
    while IFS= read -r d; do log_error "  - $d"; done <<< "$dups"
    log_error "  Renombra los FASTQ o edita la columna 'sample' para que sean únicos."
    exit 1
fi

log_info "Hoja de muestras creada: $SAMPLESHEET"
log_info "Muestras escritas: $N"
log_info "  ---- Vista previa ----"
head -n 6 "$SAMPLESHEET" | column -t -s $'\t'
log_info "  ----------------------"
log_info "Revisa el archivo y corrige los nombres de las muestras si es necesario."
log_info "(Deben ser únicos, empezar con letra y usar solo letras/números/_)."
