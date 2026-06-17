# shellcheck shell=bash
# =============================================================================
#  marcador.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Resuelve qué marcador se analiza: ITS (hongos), 16S (procariotas) o 18S
#  (microeucariotas). A partir de esa decisión elige el archivo de parámetros
#  (YAML) que recibe Nextflow. Lo llaman los scripts 02 y 03.
# =============================================================================

# seleccionar_marcador: deja listas las variables MARCADOR y CONFIG_MARCADOR.
# Si MARCADOR viene vacío de parametros.sh, lo pregunta (solo si hay terminal).
seleccionar_marcador() {
    if [ -z "${MARCADOR:-}" ]; then
        if [ -t 0 ]; then
            echo
            echo "¿Qué marcador vas a analizar?"
            echo "  1) its  → hongos (región ITS, base UNITE)"
            echo "  2) 16s  → procariotas (gen 16S rRNA, base SILVA)"
            echo "  3) 18s  → microeucariotas/protistas (gen 18S rRNA, base PR2)"
            read -r -p "Elige [1/2/3]: " resp
            case "$resp" in
                1|its|ITS|i)  MARCADOR="its" ;;
                2|16s|16S)    MARCADOR="16s" ;;
                3|18s|18S)    MARCADOR="18s" ;;
                *) log_error "opción no válida: '$resp' (elige 1, 2 o 3)"; exit 1 ;;
            esac
        else
            log_error "MARCADOR está vacío y no hay terminal para preguntar."
            log_error "Define MARCADOR=\"its\" o \"16s\" en configuracion/parametros.sh."
            exit 1
        fi
    fi

    # Aceptamos el marcador en mayúsculas o minúsculas (ITS, 18S, etc.), lo normalizamos.
    MARCADOR="$(printf '%s' "$MARCADOR" | tr '[:upper:]' '[:lower:]')"

    case "$MARCADOR" in
        its|16s|18s) : ;;
        *) log_error "MARCADOR no válido: '$MARCADOR' (usa its, 16s o 18s)"; exit 1 ;;
    esac

    # Archivo de parámetros según el marcador
    case "$MARCADOR" in
        its) CONFIG_MARCADOR="$CONFIG_ITS" ;;
        16s) CONFIG_MARCADOR="$CONFIG_16S" ;;
        18s) CONFIG_MARCADOR="$CONFIG_18S" ;;
    esac

    export MARCADOR CONFIG_MARCADOR
    log_info "Marcador: $MARCADOR  |  Parámetros: $CONFIG_MARCADOR"
}

# leer_yaml <clave> <archivo>: devuelve el valor de una clave simple del YAML
# (sin comillas), o vacío si no está. Sirve para mostrar en pantalla lo que el
# marcador trae, sin duplicar los valores en el script.
leer_yaml() {
    local clave="$1" arch="$2" val
    val="$(grep -E "^[[:space:]]*${clave}[[:space:]]*:" "$arch" 2>/dev/null | head -1)"
    [ -z "$val" ] && return 0
    val="${val#*:}"          # quita 'clave:'
    val="${val%%#*}"         # quita comentario al final de la línea
    val="${val#"${val%%[![:space:]]*}"}"   # recorta espacios a la izquierda
    val="${val%"${val##*[![:space:]]}"}"   # recorta espacios a la derecha
    val="${val#\"}"; val="${val%\"}"       # quita comillas dobles
    val="${val#\'}"; val="${val%\'}"       # quita comillas simples
    printf '%s' "$val"
}

# leer_taxonomia <archivo>: devuelve la base taxonómica activa del YAML, venga del
# clasificador que venga (DADA2, QIIME2 o SINTAX), con el clasificador entre
# paréntesis. El marcador no fija de antemano la clave: 18S puede ir por PR2
# (dada_ref_taxonomy) o por SILVA (qiime_ref_taxonomy). Vacío si no hay ninguna.
leer_taxonomia() {
    local arch="$1" val
    val="$(leer_yaml dada_ref_taxonomy "$arch")";  [ -n "$val" ] && { printf '%s (DADA2)' "$val"; return; }
    val="$(leer_yaml qiime_ref_taxonomy "$arch")"; [ -n "$val" ] && { printf '%s (QIIME2)' "$val"; return; }
    val="$(leer_yaml sintax_ref_taxonomy "$arch")"; [ -n "$val" ] && { printf '%s (SINTAX)' "$val"; return; }
}
