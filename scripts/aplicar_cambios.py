"""Aplica cambios a las preguntas de un tema sin tocar los ids.

Uso:  python scripts/aplicar_cambios.py cambios.json

cambios.json:
{
  "archivo": "alimentacion-equilibrada/tema-01.json",
  "cambios": {
    "ae-t01-001": {"pregunta": "...", "opciones": ["...", "...", "...", "..."], "correcta": 0,
                   "explicacion": "...", "orden_fijo": true}
  }
}
Solo se cambian los campos que aparecen. "orden_fijo": false lo quita.
"""
import json
import sys
from pathlib import Path

CONTENIDO = Path(__file__).resolve().parent.parent / "web" / "contenido"


def main() -> int:
    spec = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    ruta = CONTENIDO / spec["archivo"]
    datos = json.loads(ruta.read_text(encoding="utf-8"))
    cambios = dict(spec["cambios"])
    for p in datos["preguntas"]:
        c = cambios.pop(p["id"], None)
        if not c:
            continue
        for campo in ("pregunta", "opciones", "correcta", "explicacion", "dificultad"):
            if campo in c:
                p[campo] = c[campo]
        if c.get("orden_fijo"):
            p["orden_fijo"] = True
        elif "orden_fijo" in c:
            p.pop("orden_fijo", None)
    if cambios:
        print("Ids no encontrados:", ", ".join(cambios))
        return 1
    ruta.write_text(json.dumps(datos, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{spec['archivo']}: {len(spec['cambios'])} preguntas cambiadas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
