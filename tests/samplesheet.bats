#!/usr/bin/env bats
# =============================================================================
#  samplesheet.bats
#  Pruebas unitarias de derivar_nombre (scripts/01_generar_samplesheet.sh), que
#  limpia el nombre de muestra a partir del FASTQ R1. Son tres 'sed' encadenados
#  con casos límite (sufijos de Illumina, réplicas que acaban en _1, nombres que
#  no empiezan con letra); aquí se fijan para que no se rompan en silencio.
# =============================================================================

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # ponytail: cargamos SOLO las funciones desde el script sin ejecutarlo (el script
    # corre todo al sourcearse). Extraemos cada bloque con sed; si se renombra una
    # función o cambia el formato del cierre '}', actualizar el rango.
    source <(sed -n '/^derivar_nombre() {/,/^}/p' "$REPO/scripts/01_generar_samplesheet.sh")
    source <(sed -n '/^derivar_run() {/,/^}/p' "$REPO/scripts/01_generar_samplesheet.sh")
}

@test "derivar_nombre: nombre Illumina completo (_S#_L###_R1_001)" {
    run derivar_nombre "MUESTRA_S1_L001_R1_001.fastq.gz"
    [ "$output" = "MUESTRA" ]
}

@test "derivar_nombre: sufijo _R1" {
    run derivar_nombre "MUESTRA_R1.fastq.gz"
    [ "$output" = "MUESTRA" ]
}

@test "derivar_nombre: sufijo _1" {
    run derivar_nombre "MUESTRA_1.fastq.gz"
    [ "$output" = "MUESTRA" ]
}

@test "derivar_nombre: una réplica que acaba en _1 conserva ese _1 al quitar _R1" {
    run derivar_nombre "rep_1_R1.fastq.gz"
    [ "$output" = "rep_1" ]
}

@test "derivar_nombre: nombre que no empieza con letra recibe prefijo S_" {
    run derivar_nombre "123_R1.fastq.gz"
    [ "$output" = "S_123" ]
}

@test "derivar_nombre: caracteres no válidos pasan a _" {
    run derivar_nombre "muestra-A_R1.fastq.gz"
    [ "$output" = "muestra_A" ]
}

@test "derivar_nombre: también reconoce la extensión .fq.gz" {
    run derivar_nombre "MUESTRA_R1.fq.gz"
    [ "$output" = "MUESTRA" ]
}

@test "derivar_run: FASTQ suelto en CARPETA_FASTQ es la corrida 1" {
    CARPETA_FASTQ="datos/crudos"
    run derivar_run "datos/crudos/x_R1.fastq.gz"
    [ "$output" = "1" ]
}

@test "derivar_run: una subcarpeta es el nombre de la corrida" {
    CARPETA_FASTQ="datos/crudos"
    run derivar_run "datos/crudos/corridaB/x_R1.fastq.gz"
    [ "$output" = "corridaB" ]
}

@test "derivar_run: respeta una barra final en CARPETA_FASTQ" {
    CARPETA_FASTQ="datos/crudos/"
    run derivar_run "datos/crudos/x_R1.fastq.gz"
    [ "$output" = "1" ]
}

@test "derivar_run: los espacios en la subcarpeta pasan a _ (run sin espacios)" {
    CARPETA_FASTQ="datos/crudos"
    run derivar_run "datos/crudos/run 2/x_R1.fastq.gz"
    [ "$output" = "run_2" ]
}
