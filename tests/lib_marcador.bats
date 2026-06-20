#!/usr/bin/env bats
# =============================================================================
#  lib_marcador.bats
#  Pruebas unitarias de leer_yaml y leer_taxonomia (scripts/lib/marcador.sh).
#  Son el mini-parser de YAML que decide qué valor (y qué base de datos) usa la
#  corrida; aquí se cubren sus casos límite, que shellcheck no puede ver.
# =============================================================================

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # registro.sh define los log_* que marcador.sh referencia (solo en seleccionar_*,
    # que no probamos aquí); se carga para tener el archivo completo y sin sorpresas.
    source "$REPO/scripts/lib/registro.sh"
    source "$REPO/scripts/lib/marcador.sh"

    FIXT="$BATS_TEST_TMPDIR/m.yaml"
    cat > "$FIXT" <<'YAML'
FW_primer: "GTGYCAGCMGCCGCGGTAA"
cut_its: its2          # comentario al final
addsh: true
comillas_simples: 'valor'
con_espacios:    "centro"
YAML
}

@test "leer_yaml: valor entre comillas dobles, sin comillas" {
    run leer_yaml FW_primer "$FIXT"
    [ "$status" -eq 0 ]
    [ "$output" = "GTGYCAGCMGCCGCGGTAA" ]
}

@test "leer_yaml: quita el comentario al final de la línea" {
    run leer_yaml cut_its "$FIXT"
    [ "$output" = "its2" ]
}

@test "leer_yaml: quita comillas simples" {
    run leer_yaml comillas_simples "$FIXT"
    [ "$output" = "valor" ]
}

@test "leer_yaml: recorta espacios alrededor del valor" {
    run leer_yaml con_espacios "$FIXT"
    [ "$output" = "centro" ]
}

@test "leer_yaml: clave inexistente devuelve vacío" {
    run leer_yaml no_existe "$FIXT"
    [ "$output" = "" ]
}

@test "leer_yaml: lee un marcador real del repo" {
    run leer_yaml FW_primer "$REPO/configuracion/marcador_16s.yaml"
    [ "$output" = "GTGYCAGCMGCCGCGGTAA" ]
}

@test "leer_taxonomia: dada_ref_taxonomy se rotula (DADA2)" {
    echo 'dada_ref_taxonomy: "silva=138"' > "$BATS_TEST_TMPDIR/t.yaml"
    run leer_taxonomia "$BATS_TEST_TMPDIR/t.yaml"
    [ "$output" = "silva=138 (DADA2)" ]
}

@test "leer_taxonomia: qiime_ref_taxonomy se rotula (QIIME2)" {
    echo 'qiime_ref_taxonomy: "silva=138"' > "$BATS_TEST_TMPDIR/t.yaml"
    run leer_taxonomia "$BATS_TEST_TMPDIR/t.yaml"
    [ "$output" = "silva=138 (QIIME2)" ]
}

@test "leer_taxonomia: DADA2 tiene prioridad sobre QIIME2 si están ambas" {
    printf 'dada_ref_taxonomy: "pr2=5.1.0"\nqiime_ref_taxonomy: "silva=138"\n' > "$BATS_TEST_TMPDIR/t.yaml"
    run leer_taxonomia "$BATS_TEST_TMPDIR/t.yaml"
    [ "$output" = "pr2=5.1.0 (DADA2)" ]
}

@test "leer_taxonomia: sin ninguna clave devuelve vacío" {
    echo 'FW_primer: "ACGT"' > "$BATS_TEST_TMPDIR/t.yaml"
    run leer_taxonomia "$BATS_TEST_TMPDIR/t.yaml"
    [ "$output" = "" ]
}

@test "leer_taxonomia: el 18s real va por PR2/DADA2" {
    run leer_taxonomia "$REPO/configuracion/marcador_18s.yaml"
    [ "$output" = "pr2=5.1.0 (DADA2)" ]
}
