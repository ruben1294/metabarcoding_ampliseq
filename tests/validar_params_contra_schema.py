#!/usr/bin/env python3
# =============================================================================
#  validar_params_contra_schema.py
#  Autor: Rubén Castañeda-Martínez
# -----------------------------------------------------------------------------
#  Comprueba que cada clave de un params-file generado por 03_ejecutar_ampliseq.sh
#  exista como parámetro real en el nextflow_schema.json de nf-core/ampliseq. Sirve
#  para atrapar un emitir_* con la llave mal escrita o renombrada: ni shellcheck ni
#  'nextflow config' lo ven, y el esquema de ampliseq no trae additionalProperties,
#  así que la validación normal solo avisaría en vez de fallar.
#
#  Uso:  python3 tests/validar_params_contra_schema.py <schema.json> <params.yaml> [params2.yaml ...]
#  Sale con código 1 si algún archivo tiene una clave que no está en el esquema.
# =============================================================================
import json
import re
import sys

# ponytail: el params-file es YAML plano (clave: valor por línea), así que sacamos las
# claves con una regex en vez de depender de pyyaml. Si algún día se anidan claves, hay
# que pasar a un parser de YAML de verdad.
LINEA_CLAVE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:")


def claves_validas(ruta_schema):
    """Nombres de parámetro declarados en el esquema (bajo $defs.*.properties)."""
    with open(ruta_schema) as fh:
        esquema = json.load(fh)
    claves = set()
    # ampliseq agrupa los parámetros en $defs; algunos esquemas también traen
    # 'properties' en la raíz, así que cubrimos ambos.
    for grupo in esquema.get("$defs", {}).values():
        claves.update(grupo.get("properties", {}).keys())
    claves.update(esquema.get("properties", {}).keys())
    return claves


def claves_emitidas(ruta_params):
    """Claves del params-file, ignorando comentarios y líneas en blanco."""
    claves = []
    with open(ruta_params) as fh:
        for linea in fh:
            if linea.lstrip().startswith("#"):
                continue
            m = LINEA_CLAVE.match(linea)
            if m:
                claves.append(m.group(1))
    return claves


def main(argv):
    if len(argv) < 3:
        print("uso: validar_params_contra_schema.py <schema.json> <params.yaml> [...]", file=sys.stderr)
        return 2
    ruta_schema, rutas_params = argv[1], argv[2:]
    validas = claves_validas(ruta_schema)
    print(f"Esquema: {ruta_schema}  ({len(validas)} parámetros)")

    hubo_error = False
    for ruta in rutas_params:
        emitidas = claves_emitidas(ruta)
        desconocidas = [k for k in emitidas if k not in validas]
        if desconocidas:
            hubo_error = True
            print(f"FALLO  {ruta}: {len(desconocidas)} clave(s) fuera del esquema:")
            for k in desconocidas:
                print(f"          - {k}")
        else:
            print(f"OK     {ruta}: {len(emitidas)} claves, todas en el esquema")
    return 1 if hubo_error else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
