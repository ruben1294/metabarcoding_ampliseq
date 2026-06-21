# shellcheck shell=bash
# =============================================================================
#  registro.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Funciones de registro (logging) comunes a todos los scripts. Cada línea lleva
#  marca de tiempo y nivel:  [YYYY-MM-DD HH:MM:SS] [NIVEL] mensaje
#  INFO/WARN/DEBUG van a stdout (archivo .out) y ERROR a stderr (archivo .err).
#
#  Uso típico, al inicio del script y después de cargar parametros.sh:
#       source "scripts/lib/registro.sh"
#       iniciar_registro "03_ejecutar_ampliseq"
#       activar_trap_errores          # opcional: aborta y registra al primer error
#       cabecera_registro "Mi pipeline"
#       log_info "Comenzando…"
# =============================================================================

# Paleta de colores por nivel. Quedan vacías ("") cuando el color está apagado,
# así la salida de los logs es texto plano sin tocar las funciones.
C_INFO=""; C_WARN=""; C_ERROR=""; C_DEBUG=""; C_RESET=""

# Si la salida es una terminal, se activa el color.
# Se puede forzar con LOG_COLOR=si / LOG_COLOR=no, o apagar con NO_COLOR=1.
_configurar_colores() {
    local usar="no"
    case "${LOG_COLOR:-auto}" in
        si|yes|force|always|1) usar="si" ;;
        no|none|never|0)       usar="no" ;;
        *) [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && usar="si" ;;
    esac
    if [ "$usar" = "si" ]; then
        C_INFO=$'\033[0;32m'    # verde
        C_WARN=$'\033[0;33m'    # amarillo
        C_ERROR=$'\033[1;31m'   # rojo
        C_DEBUG=$'\033[0;36m'   # cian
        C_RESET=$'\033[0m'
    else
        C_INFO=""; C_WARN=""; C_ERROR=""; C_DEBUG=""; C_RESET=""
    fi
}
_configurar_colores

# Cuenta los errores registrados con log_error. Un verificador (p. ej. el script
# 02) lo consulta al final para salir con código ≠ 0 si hubo problemas, sin abortar
# en el primero. Ojo: un log_error dentro de un subshell no actualiza este contador.
LOG_ERRORES=0

# Se usa printf con %s para el mensaje
log_info()  { printf '%s[%s] [INFO] %s%s\n'  "$C_INFO"  "$(date '+%Y-%m-%d %H:%M:%S')" "$*" "$C_RESET"; }
log_warn()  { printf '%s[%s] [WARN] %s%s\n'  "$C_WARN"  "$(date '+%Y-%m-%d %H:%M:%S')" "$*" "$C_RESET"; }
log_error() { LOG_ERRORES=$((LOG_ERRORES + 1)); printf '%s[%s] [ERROR] %s%s\n' "$C_ERROR" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" "$C_RESET" >&2; }
log_debug() { printf '%s[%s] [DEBUG] %s%s\n' "$C_DEBUG" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" "$C_RESET"; }

# iniciar_registro <nombre> [carpeta_logs]
# Empieza a guardar el log en disco, separado por nivel:
#   <carpeta_logs>/<nombre>_<sello>.out   ← stdout (INFO/WARN/DEBUG)
#   <carpeta_logs>/<nombre>_<sello>.err   ← stderr (ERROR)
# Mantiene la salida en la terminal con color y guarda los archivos en texto
# plano. Respeta un $SELLO ya definido para compartir marca de tiempo con otros
# archivos del script; si no existe, lo crea y lo exporta. Deja las rutas en
# LOG_OUT y LOG_ERR.
iniciar_registro() {
    local nombre="${1:?iniciar_registro: falta el nombre base del log}"
    local dir_logs="${2:-${DIR_LOGS:-logs}}"

    SELLO="${SELLO:-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$dir_logs"
    LOG_OUT="${dir_logs}/${nombre}_${SELLO}.out"
    LOG_ERR="${dir_logs}/${nombre}_${SELLO}.err"

    # Decidir el color con la terminal real, antes de redirigir la salida.
    _configurar_colores

    # Quitamos los códigos ANSI para que los archivos queden limpios.
    local quita_ansi='s/\x1b\[[0-9;]*[A-Za-z]//g'
    exec > >(tee >(sed -u "$quita_ansi" >> "$LOG_OUT")) \
        2> >(tee >(sed -u "$quita_ansi" >> "$LOG_ERR") >&2)

    log_info "Registro iniciado (sello: $SELLO)"
    log_info "  stdout (INFO/WARN/DEBUG) → $LOG_OUT"
    log_info "  stderr (ERROR)           → $LOG_ERR"
}

# activar_trap_errores: ante el primer comando que falle, registra dónde y con
# qué código, y aborta. Úsalo solo en scripts con 'set -e' (no en el verificador
# 02, que debe seguir reportando todo aunque algo falle).
activar_trap_errores() {
    trap 'log_error "El script falló en la línea $LINENO con código de salida $?"; exit 1' ERR
}

# cabecera_registro [titulo]: imprime una cabecera con la información de la corrida.
cabecera_registro() {
    local titulo="${1:-Pipeline}"
    log_info "=========================================="
    log_info "$titulo"
    log_info "=========================================="
    log_info "Proyecto: ${PROYECTO:-N/A}"
    log_info "Host: $(hostname)"
    log_info "Usuario: ${USER:-$(whoami)}"
    log_info "Directorio: $(pwd)"
    log_info "Inicio: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "=========================================="
}
