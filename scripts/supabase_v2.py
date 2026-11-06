"""Herramientas para el esquema v2 de NutriTest en Supabase (ver supabase/v2/LEEME.md).

Uso:
  python scripts/supabase_v2.py subir-preguntas      sube web/contenido/** a la tabla preguntas
  python scripts/supabase_v2.py migrar-progreso      copia perfiles, respuestas, exámenes y ocultas
                                                     del proyecto antiguo al nuevo (una sola vez)

Variables de entorno (o un archivo .env en la raíz, que NO se sube a GitHub):
  SUPABASE_URL          https://<proyecto-nuevo>.supabase.co
  SUPABASE_SECRET_KEY   sb_secret_...   (Settings → API Keys; nunca en el código ni en la web)
  ANTIGUO_URL / ANTIGUO_KEY   proyecto antiguo (solo migrar-progreso); si no se ponen,
                              se leen de web/js/config.js, que aún apunta al antiguo

Solo usa la biblioteca estándar de Python.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
CONTENIDO = RAIZ / "web" / "contenido"
ESQUEMA = "dietetica"
LOTE = 500


def cargar_env() -> None:
    env = RAIZ / ".env"
    if not env.exists():
        return
    for linea in env.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if linea and not linea.startswith("#") and "=" in linea:
            clave, valor = linea.split("=", 1)
            os.environ.setdefault(clave.strip(), valor.strip().strip('"').strip("'"))


def config_antigua() -> None:
    """Rellena ANTIGUO_URL y ANTIGUO_KEY con los valores de web/js/config.js."""
    import re
    texto = (RAIZ / "web" / "js" / "config.js").read_text(encoding="utf-8")
    url = re.search(r"SUPABASE_URL\s*=\s*'([^']+)'", texto)
    key = re.search(r"SUPABASE_KEY\s*=\s*'([^']+)'", texto)
    if url:
        os.environ.setdefault("ANTIGUO_URL", url.group(1))
    if key:
        os.environ.setdefault("ANTIGUO_KEY", key.group(1))


def variable(nombre: str) -> str:
    valor = os.environ.get(nombre, "").strip()
    if not valor:
        sys.exit(f"Falta la variable {nombre} (en el entorno o en .env)")
    valor = valor.rstrip("/")
    if nombre.endswith("URL") and valor.endswith("/rest/v1"):  # Supabase muestra así la «API URL»
        valor = valor[: -len("/rest/v1")]
    return valor


def peticion(base: str, clave: str, metodo: str, ruta: str, cuerpo=None, prefer: str | None = None):
    cabeceras = {
        "apikey": clave,
        "Accept-Profile": ESQUEMA,
        "Content-Profile": ESQUEMA,
        "Content-Type": "application/json",
    }
    # Las claves secret también van en Authorization (igual que el worker de Monitor Vuelos)
    if not clave.startswith("sb_publishable_"):
        cabeceras["Authorization"] = f"Bearer {clave}"
    if prefer:
        cabeceras["Prefer"] = prefer
    datos = json.dumps(cuerpo).encode("utf-8") if cuerpo is not None else None
    req = urllib.request.Request(f"{base}/rest/v1/{ruta}", data=datos, method=metodo, headers=cabeceras)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            texto = r.read().decode("utf-8")
            return json.loads(texto) if texto else None
    except urllib.error.HTTPError as e:
        sys.exit(f"Supabase {e.code} en {metodo} {ruta}: {e.read().decode('utf-8', 'replace')}")


def leer_todo(base: str, clave: str, ruta: str) -> list[dict]:
    """Lee una tabla entera por páginas de 1000 filas."""
    filas, desde = [], 0
    while True:
        sep = "&" if "?" in ruta else "?"
        pagina = peticion(base, clave, "GET", f"{ruta}{sep}limit=1000&offset={desde}")
        filas += pagina
        if len(pagina) < 1000:
            return filas
        desde += 1000


# ---------------------------------------------------------------- preguntas
def filas_preguntas() -> list[dict]:
    catalogo = json.loads((CONTENIDO / "libros.json").read_text(encoding="utf-8"))
    fuentes = []  # (libro, tema, archivo)
    for libro in catalogo["libros"]:
        for tema in libro.get("temas", []):
            fuentes.append((libro["id"], tema["id"], CONTENIDO / libro["id"] / tema["archivo"]))
    indice = CONTENIDO / "oficiales" / "indice.json"
    if indice.exists():
        for ex in json.loads(indice.read_text(encoding="utf-8"))["examenes"]:
            fuentes.append(("oficiales", ex["id"], CONTENIDO / "oficiales" / ex["archivo"]))

    filas = []
    for libro, tema, archivo in fuentes:
        preguntas = json.loads(archivo.read_text(encoding="utf-8"))["preguntas"]
        for orden, p in enumerate(preguntas, start=1):
            filas.append({
                "id": p["id"], "libro": libro, "tema": tema, "orden": orden,
                "numero": p.get("numero"), "pregunta": p["pregunta"], "opciones": p["opciones"],
                "correcta": p["correcta"], "explicacion": p.get("explicacion", ""),
                "dificultad": p.get("dificultad"), "orden_fijo": bool(p.get("orden_fijo", False)),
                "referencia": p.get("referencia"), "activa": True,
            })
    return filas


def subir_preguntas() -> None:
    base, clave = variable("SUPABASE_URL"), variable("SUPABASE_SECRET_KEY")
    filas = filas_preguntas()
    ids = {f["id"] for f in filas}
    if len(ids) != len(filas):
        sys.exit("Hay ids de pregunta repetidos: ejecuta antes scripts/validar_preguntas.py")
    for i in range(0, len(filas), LOTE):
        peticion(base, clave, "POST", "preguntas?on_conflict=id", filas[i:i + LOTE],
                 prefer="resolution=merge-duplicates,return=minimal")
    # Las que ya no están en los archivos se desactivan (no se borran: hay respuestas que las citan)
    en_bd = {f["id"] for f in leer_todo(base, clave, "preguntas?select=id&activa=eq.true")}
    retiradas = sorted(en_bd - ids)
    for i in range(0, len(retiradas), 100):
        lista = ",".join(f'"{x}"' for x in retiradas[i:i + 100])
        peticion(base, clave, "PATCH", f"preguntas?id=in.({lista})", {"activa": False}, prefer="return=minimal")
    print(f"Preguntas subidas: {len(filas)} · desactivadas: {len(retiradas)}")


# ---------------------------------------------------------------- progreso
def migrar_progreso() -> None:
    config_antigua()
    nuevo, clave_nueva = variable("SUPABASE_URL"), variable("SUPABASE_SECRET_KEY")
    antiguo, clave_antigua = variable("ANTIGUO_URL"), variable("ANTIGUO_KEY")
    if nuevo == antiguo:
        sys.exit("ANTIGUO_URL y SUPABASE_URL son el mismo proyecto")

    # Los perfiles migrados llegan sin cuenta (user_id vacío) hasta 02_vincular_cuentas.sql.
    # Si ya hay alguno, o si ya hay respuestas de perfiles migrados, la migración ya se hizo.
    ya = peticion(nuevo, clave_nueva, "GET", "perfiles?select=id&user_id=is.null&limit=1")
    if ya:
        sys.exit("El proyecto nuevo ya tiene perfiles migrados: la migración ya se hizo (no se repite para no duplicar)")

    perfiles = leer_todo(antiguo, clave_antigua, "perfiles?select=id,nombre,avatar,color,creado_en")
    respuestas = leer_todo(antiguo, clave_antigua,
                           "respuestas?select=perfil_id,pregunta_id,libro,tema,acertada,modo,fecha&order=id")
    examenes = leer_todo(antiguo, clave_antigua,
                         "examenes?select=perfil_id,tipo,libros,n_preguntas,aciertos,fallos,blancos,nota,segundos,detalle,fecha&order=id")
    try:
        ocultas = leer_todo(antiguo, clave_antigua, "ocultas?select=perfil_id,pregunta_id,fecha")
    except SystemExit:
        ocultas = []

    print(f"Antiguo: {len(perfiles)} perfiles, {len(respuestas)} respuestas, "
          f"{len(examenes)} exámenes, {len(ocultas)} ocultas")
    for p in perfiles:
        print(f"  · {p['nombre']}  ({p['id']})")

    peticion(nuevo, clave_nueva, "POST", "perfiles", perfiles, prefer="return=minimal")
    for tabla, filas in (("respuestas", respuestas), ("examenes", examenes), ("ocultas", ocultas)):
        for i in range(0, len(filas), LOTE):
            peticion(nuevo, clave_nueva, "POST", tabla, filas[i:i + LOTE], prefer="return=minimal")

    # Comprobación
    for tabla, filas in (("perfiles", perfiles), ("respuestas", respuestas), ("examenes", examenes), ("ocultas", ocultas)):
        n = len(leer_todo(nuevo, clave_nueva, f"{tabla}?select=perfil_id" if tabla != "perfiles" else "perfiles?select=id"))
        estado = "OK" if n == len(filas) else "NO COINCIDE"
        print(f"{tabla}: antiguo {len(filas)} · nuevo {n}  {estado}")
    print("Siguiente paso: supabase/v2/02_vincular_cuentas.sql")


def main() -> None:
    cargar_env()
    ordenes = {"subir-preguntas": subir_preguntas, "migrar-progreso": migrar_progreso}
    if len(sys.argv) != 2 or sys.argv[1] not in ordenes:
        sys.exit(__doc__)
    ordenes[sys.argv[1]]()


if __name__ == "__main__":
    main()
