# Supabase v2: cuentas, accesos y seguridad

NutriTest se muda al proyecto de Supabase **«Monitor Vuelos Joan»**, en su propio esquema `dietetica`.
El proyecto antiguo («Academia Jan») sigue funcionando hasta el final: la web actual no se toca en esta fase.

## Pasos, en orden

| # | Dónde | Qué |
|---|---|---|
| 1 | SQL Editor del proyecto «Monitor Vuelos Joan» | Ejecutar `Monitor Vuelos Joan/monitor-vuelos/db/migration_014_lista_blanca_usuarios.sql`. Al final sale una tabla: todas las filas con `rls_activada = true` y la condición con `es_usuario_vuelos()`. |
| 2 | GitHub de Monitor Vuelos | Subir el cambio de `web/supabase_auth.py` (Render lo despliega solo). **Después** del paso 1, nunca antes. Comprobar que sigues entrando en la web de vuelos. |
| 3 | Authentication → Sign In / Providers | Email activado · **Allow new users to sign up**: sí · **Confirm email**: no. |
| 4 | Authentication → Policies (o Passwords) | Longitud mínima de contraseña: 8. |
| 5 | SQL Editor | Ejecutar `01_esquema.sql` entero. Se puede repetir sin romper nada. |
| 6 | Settings → API → Data API | En **Exposed schemas** añadir `dietetica` y guardar. |
| 7 | SQL Editor | Ejecutar `99_pruebas.sql`. Debe salir **TODAS LAS PRUEBAS OK**. No deja nada guardado. |
| 8 | Tu ordenador | Crear `.env` en la raíz del proyecto (no se sube a GitHub) con `SUPABASE_URL=` y `SUPABASE_SECRET_KEY=` del proyecto nuevo (Settings → API Keys). |
| 9 | Tu ordenador | `python scripts/supabase_v2.py subir-preguntas` |
| 10 | Authentication → Users + SQL Editor | **Add user** para Joan (*Auto Confirm User*) y `04_crear_admin.sql` con su email: queda como administrador. |
| — | **El día del cambio** (no antes: Julie sigue usando la web antigua y se perdería su progreso) | |
| 11 | Tu ordenador | `python scripts/supabase_v2.py migrar-progreso` (copia los perfiles, respuestas, exámenes y ocultas del proyecto antiguo). |
| 12 | Authentication → Users + SQL Editor | **Add user** para Julie y `02_vincular_cuentas.sql` con los dos emails: une los perfiles antiguos a las cuentas (el perfil nuevo de Joan se junta con el antiguo). |
| 13 | SQL Editor | Volver a ejecutar `99_pruebas.sql` para confirmar. |

Hechos el 2026-11-06: pasos 1 a 10 (demo de 2 días con `03_demo_2_dias.sql`). `diagnostico.sql` solo lee permisos, por si una prueba falla.

## Qué protege cada cosa

- **Sin sesión no se ve nada.** El rol `anon` (cualquiera con la clave pública) no tiene permiso ni sobre el esquema.
- **Preguntas.** No se pueden leer de la tabla. Solo con `pedir_preguntas()`, que comprueba el acceso y el límite diario y **no envía la solución**.
- **Soluciones.** Solo salen de `responder()` y `ver_preguntas()`, y solo de preguntas ya entregadas a esa persona. La corrección la hace el servidor, así que el ranking no se puede falsear.
- **Límite diario.** Va por usuario y por día (hora de España). Repetir las preguntas de hoy no gasta más. Hay un valor general (100 al empezar) y otro por persona; «sin límite» es ilimitado.
- **Saldo, fechas y rol.** Ningún usuario puede cambiarlos. Solo con `comprar_con_saldo()` o las funciones `admin_*`, que quedan apuntadas en `registro_admin`.
- **Monitor Vuelos.** Solo entran las cuentas de `vuelos_usuarios`. Las de NutriTest no ven ni crean nada allí.

## Funciones disponibles

- **App:** `mi_estado`, `registrarme`, `pedir_preguntas`, `responder`, `ver_preguntas`, `ranking`, `comprar_con_saldo`.
- **Administrador:** `admin_usuarios`, `admin_actualizar_usuario`, `admin_dar_saldo`, `admin_ajustes`, `admin_guardar_plan`, `admin_metricas`, `admin_registro`.
- **Solo servidor (Secret Key):** `aplicar_compra_stripe`, para la fase de Stripe.

## Limitaciones conocidas

- Sin dominio propio, Supabase solo envía emails a tu equipo. Por eso no se confirma el email, y el cambio de contraseña lo hará el administrador desde el panel. Eso necesita una función de servidor (fase Netlify).
- Un examen oficial largo, como País Vasco con 154 preguntas, se corta si el límite diario es menor. El administrador y quien tenga «sin límite» no tienen ese problema.
