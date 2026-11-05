"""Comprueba que todas las preguntas están bien formadas y actualiza el recuento en libros.json.

Uso:  python scripts/validar_preguntas.py
Sale con código 1 si encuentra errores (así no se publica nada roto).
"""
import json
import sys
from collections import Counter
from pathlib import Path

CONTENIDO = Path(__file__).resolve().parent.parent / "web" / "contenido"
PROHIBIDAS = ("todas las anteriores", "ninguna de las anteriores", "todas son correctas", "a y b son correctas")


def main() -> int:
    catalogo_ruta = CONTENIDO / "libros.json"
    catalogo = json.loads(catalogo_ruta.read_text(encoding="utf-8"))
    errores, avisos, ids = [], [], set()
    total = 0

    for libro in catalogo["libros"]:
        for clave in ("id", "nombre", "icono", "color", "temas"):
            if clave not in libro:
                errores.append(f"Libro sin '{clave}': {libro.get('id', libro)}")
        if libro.get("temas") and not libro.get("prefijo"):
            errores.append(f"Libro {libro['id']}: tiene temas pero le falta 'prefijo' (para los ids de pregunta)")
            continue
        if libro.get("estado") == "proximamente" and libro.get("temas"):
            avisos.append(f"Libro {libro['id']}: está 'proximamente' pero ya tiene temas (no saldrá en la web)")
        for tema in libro.get("temas", []):
            ruta = CONTENIDO / libro["id"] / tema["archivo"]
            donde = f"{libro['id']}/{tema['archivo']}"
            if not ruta.exists():
                errores.append(f"{donde}: no existe el archivo")
                continue
            datos = json.loads(ruta.read_text(encoding="utf-8"))
            preguntas = datos.get("preguntas", [])
            reparto = Counter()
            for n, p in enumerate(preguntas, 1):
                ref = f"{donde} #{n} ({p.get('id', '?')})"
                pid = p.get("id", "")
                if not pid.startswith(f"{libro['prefijo']}-{tema['id']}-"):
                    errores.append(f"{ref}: el id debe empezar por {libro['prefijo']}-{tema['id']}-")
                if pid in ids:
                    errores.append(f"{ref}: id repetido")
                ids.add(pid)
                if not p.get("pregunta", "").strip():
                    errores.append(f"{ref}: falta el enunciado")
                ops = p.get("opciones", [])
                if len(ops) != 4:
                    errores.append(f"{ref}: debe tener 4 opciones (tiene {len(ops)})")
                if len({o.strip().lower() for o in ops}) != len(ops):
                    errores.append(f"{ref}: opciones repetidas")
                if any(any(x in o.lower() for x in PROHIBIDAS) for o in ops):
                    errores.append(f"{ref}: no usar 'todas/ninguna de las anteriores' (las opciones se barajan)")
                if p.get("correcta") not in (0, 1, 2, 3):
                    errores.append(f"{ref}: 'correcta' debe ser 0, 1, 2 o 3")
                else:
                    reparto[p["correcta"]] += 1
                if not p.get("explicacion", "").strip():
                    errores.append(f"{ref}: falta la explicación")
            if len(preguntas) >= 12 and reparto and max(reparto.values()) > len(preguntas) * 0.4:
                avisos.append(f"{donde}: la respuesta correcta está muy concentrada {dict(reparto)}")
            tema["preguntas"] = len(preguntas)
            total += len(preguntas)

    for a in avisos:
        print("AVISO:", a)
    if errores:
        for e in errores:
            print("ERROR:", e)
        print(f"\n{len(errores)} errores. No se ha actualizado libros.json.")
        return 1

    catalogo_ruta.write_text(json.dumps(catalogo, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Todo correcto: {total} preguntas en {sum(len(l['temas']) for l in catalogo['libros'])} temas. libros.json actualizado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
