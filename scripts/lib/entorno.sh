# shellcheck shell=bash
# =============================================================================
#  entorno.sh
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Resuelve dónde corre el flujo: en local (tu computadora) o en un HPC con
#  SLURM. A partir de esa decisión fija el motor de contenedor y el archivo de
#  recursos que usará Nextflow. Lo llaman los scripts 00, 02 y 03.
# =============================================================================

# seleccionar_entorno: deja listas las variables ENTORNO, MOTOR y CONFIG_RECURSOS.
# Si ENTORNO viene vacío de parametros.sh, lo pregunta (solo si hay terminal).
seleccionar_entorno() {
    # Preguntar solo si no se fijó en parametros.sh
    if [ -z "${ENTORNO:-}" ]; then
        if [ -t 0 ]; then
            echo
            echo "¿Dónde correrás el análisis?"
            echo "  1) local: tu computadora (Docker y núcleos de la computadora)"
            echo "  2) hpc: clúster con SLURM (Docker u otro motor en los nodos de cómputo y cola de trabajos)"
            read -r -p "Elige [1/2]: " resp
            case "$resp" in
                1|local|Local|LOCAL|l) ENTORNO="local" ;;
                2|hpc|Hpc|HPC|h)       ENTORNO="hpc" ;;
                *) log_error "opción no válida: '$resp' (elige 1 o 2)"; exit 1 ;;
            esac
        else
            log_error "ENTORNO está vacío y no hay terminal para preguntar."
            log_error "Define ENTORNO=\"local\" o \"hpc\" en configuracion/parametros.sh."
            exit 1
        fi
    fi

    case "$ENTORNO" in
        local|hpc) : ;;
        *) log_error "ENTORNO no válido: '$ENTORNO' (usa local o hpc)"; exit 1 ;;
    esac

    # Motor por defecto: Docker en local y en HPC.
    # Cámbialo en parametros.sh solo si quieres forzar otro.
    if [ "${MOTOR:-auto}" = "auto" ]; then
        MOTOR="docker"
    fi

    # Archivo de recursos según el entorno
    [ "$ENTORNO" = "local" ] && CONFIG_RECURSOS="$CONFIG_LOCAL" || CONFIG_RECURSOS="$CONFIG_HPC"

    export ENTORNO MOTOR CONFIG_RECURSOS
    log_info "Entorno: $ENTORNO  |  Motor: $MOTOR  |  Recursos: $CONFIG_RECURSOS"
}
