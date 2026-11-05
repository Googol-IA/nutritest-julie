# NutriTest de Julie · FP Superior de Dietética

Web de tests para estudiar el FP Superior de Dietética, pensada para el móvil.
Web estática (GitHub Pages) + progreso en Supabase (esquema `dietetica`).

## Estado

Web publicada: https://googol-ia.github.io/nutritest-julie/ (repo `Googol-IA/nutritest-julie`).

| Fase | Estado |
|---|---|
| 1. Proyecto + SQL de Supabase | ✅ Hecho y conectado (proyecto `aekyogcjrwbdzvrfcmaf`, esquema `dietetica`) |
| 2. Web completa | ✅ Hecho y probado |
| 3. GitHub + publicación automática | ✅ Hecho |
| 4. Preguntas | ✅ Control alimentario T1-T5, Dietoterapia T1-T4, Alimentación equilibrada T1-T4 (652 preguntas) |

**Temario:** `G:\.shortcut-targets-by-id\1WDnZhOePi0y49cmZM1vf0ron75TTGUYh\Apuntes FP dietética\<Libro>\`.
Las preguntas se generan **solo con los PDF que llevan «diapo» en el nombre** (el resto se ignora).

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
