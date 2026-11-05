# NutriTest de Julie · FP Superior de Dietética

Web de tests para estudiar el FP Superior de Dietética, pensada para el móvil.
Web estática (GitHub Pages) + progreso en Supabase (esquema `dietetica`).

## Estado

| Fase | Estado |
|---|---|
| 1. Proyecto + SQL de Supabase | ✅ Hecho — **falta ejecutar el SQL en Supabase** |
| 2. Web completa (con 12 preguntas de ejemplo) | ✅ Hecho y probado en modo local |
| 3. GitHub + publicación automática | ⏳ Pendiente |
| 4. Preguntas de los temas reales | ⏳ Pendiente (falta la ruta de los PDF) |

## Puesta en marcha de Supabase (una vez)
1. Supabase → **SQL Editor** → pegar `supabase/01_esquema.sql` → *Run*.
2. **Settings → API → Exposed schemas** → añadir `dietetica` → *Save*.
3. Copiar la *Project URL* y la clave *anon / publishable* en `web/js/config.js`.

Mientras `config.js` esté vacío, la web funciona en **modo local** (progreso guardado solo en ese navegador).

## Cómo se añaden temas
1. Joan deja el PDF del tema en la carpeta del temario (fuera de GitHub).
2. Claude lee el PDF y crea `web/contenido/<libro>/tema-NN.json` con ~40 preguntas.
3. Se añade el tema en `web/contenido/libros.json`.
4. `python scripts/validar_preguntas.py` (comprueba todo y actualiza los recuentos).
5. `git commit` + `git push` → la web se actualiza sola en 1–2 minutos.

Formato de cada pregunta:
```json
{ "id": "ca-t01-017", "pregunta": "…", "opciones": ["…","…","…","…"],
  "correcta": 2, "explicacion": "…", "dificultad": 1 }
```
- `id` = prefijo del libro + tema + número. **No cambiar ids existentes** (el historial de cada perfil se basa en ellos).
- `correcta` = posición (0–3) de la opción buena. Las opciones se barajan al mostrarse, así que no usar «todas las anteriores».

## Cómo se añade un libro nuevo
Añadir una entrada en `web/contenido/libros.json` (id, nombre, prefijo de 2 letras, icono, color, `temas: []`) y crear la carpeta `web/contenido/<id>/`.

## Ajustes
`web/js/config.js`: penalización del simulacro (por defecto 1/3: 3 fallos restan 1 acierto) y minutos por pregunta.

## Probar en el PC
```bash
python -m http.server 8765 --directory web
```
y abrir http://localhost:8765
