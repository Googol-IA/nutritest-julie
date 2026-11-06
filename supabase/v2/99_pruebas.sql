-- =====================================================================
-- NutriTest · Pruebas de seguridad del esquema v2
-- SQL Editor → pega el archivo entero → Run.
-- Crea usuarios y preguntas de prueba, hace las comprobaciones como si fuera
-- cada usuario y al final lo DESHACE TODO (rollback): no deja nada guardado.
-- Si todo va bien, el resultado es una fila: «TODAS LAS PRUEBAS OK».
-- Si algo falla, sale un error que empieza por «FALLO:».
-- =====================================================================

begin;

-- ---------- Preparación (como administrador de la base de datos) -------
insert into auth.users (id, email) values
  ('eeeeeeee-0000-0000-0000-00000000000a', 'prueba-alumna-a@nutritest.test'),
  ('eeeeeeee-0000-0000-0000-00000000000b', 'prueba-alumna-b@nutritest.test'),
  ('eeeeeeee-0000-0000-0000-00000000000c', 'prueba-admin@nutritest.test'),
  ('eeeeeeee-0000-0000-0000-00000000000d', 'prueba-vuelos-no@nutritest.test');

insert into dietetica.preguntas (id, libro, tema, orden, pregunta, opciones, correcta, explicacion) values
  ('zz-prueba-001', 'zz-prueba', 't01', 1, '¿Uno?',  '["a","b","c"]', 0, 'Porque sí'),
  ('zz-prueba-002', 'zz-prueba', 't01', 2, '¿Dos?',  '["a","b","c"]', 1, 'Porque sí'),
  ('zz-prueba-003', 'zz-prueba', 't01', 3, '¿Tres?', '["a","b","c"]', 2, 'Porque sí'),
  ('zz-prueba-004', 'zz-prueba', 't02', 1, '¿Cuatro?', '["a","b"]', 1, 'Porque sí');

update dietetica.ajustes set limite_diario = 2, dias_demo = 7, saldo_bienvenida = 0, registro_abierto = true;

-- ---------- 0. Ninguna regla abierta (p. ej. restos del esquema antiguo) -
do $$
declare t text;
begin
  select tablename || ' / ' || policyname into t from pg_policies
  where schemaname = 'dietetica'
    and ('anon' = any (roles) or 'public' = any (roles)
         or (coalesce(qual, '') = 'true' and tablename <> 'ajustes')
         or coalesce(with_check, '') = 'true')
  limit 1;
  if t is not null then raise exception 'FALLO: hay una regla abierta en dietetica: %', t; end if;
  select table_name into t from information_schema.role_table_grants
  where table_schema = 'dietetica' and grantee in ('anon', 'PUBLIC') limit 1;
  if t is not null then raise exception 'FALLO: la clave pública tiene permisos sobre dietetica.%', t; end if;
end $$;

-- ---------- 1. Sin sesión (clave pública): no se ve nada ---------------
set local role anon;
select set_config('request.jwt.claims', '', true);
do $$ begin
  perform 1 from dietetica.preguntas limit 1;
  raise exception 'FALLO: sin sesión se pueden leer las preguntas';
exception when insufficient_privilege then null; end $$;
do $$ begin
  perform 1 from dietetica.usuarios limit 1;
  raise exception 'FALLO: sin sesión se pueden leer los usuarios';
exception when insufficient_privilege then null; end $$;
do $$ begin
  perform dietetica.pedir_preguntas('[{"libro":"zz-prueba"}]');
  raise exception 'FALLO: sin sesión se pueden pedir preguntas';
exception when insufficient_privilege then null; end $$;
reset role;

-- ---------- 2. Alumna A se registra: demo y límite --------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare e jsonb; r jsonb;
begin
  e := dietetica.mi_estado();
  if (e->>'registrado')::boolean then raise exception 'FALLO: A ya estaba registrada'; end if;
  e := dietetica.registrarme('Prueba A');
  if not (e->>'tiene_acceso')::boolean then raise exception 'FALLO: A no recibe la demo'; end if;

  -- leer preguntas directamente: prohibido
  begin
    perform 1 from dietetica.preguntas limit 1;
    raise exception 'FALLO: A puede leer la tabla de preguntas';
  exception when insufficient_privilege then null; end;

  -- pedir 3 preguntas con límite 2: recibe 2, sin solución
  r := dietetica.pedir_preguntas('[{"libro":"zz-prueba","tema":"t01"}]', null, null, false);
  if jsonb_array_length(r->'preguntas') <> 2 then
    raise exception 'FALLO: el límite diario no se aplica (recibe %)', jsonb_array_length(r->'preguntas');
  end if;
  if not (r->>'cortado')::boolean then raise exception 'FALLO: no avisa de que se ha cortado'; end if;
  if (r->'preguntas'->0) ? 'correcta' or (r->'preguntas'->0) ? 'explicacion' then
    raise exception 'FALLO: pedir_preguntas incluye la solución';
  end if;

  -- volver a pedir las mismas no gasta más
  r := dietetica.pedir_preguntas(null, array['zz-prueba-001', 'zz-prueba-002']);
  if jsonb_array_length(r->'preguntas') <> 2 then raise exception 'FALLO: repetir las de hoy gasta límite'; end if;

  -- la tercera ya no se entrega
  r := dietetica.pedir_preguntas(null, array['zz-prueba-003']);
  if jsonb_array_length(r->'preguntas') <> 0 then raise exception 'FALLO: se supera el límite diario'; end if;

  -- responder: el servidor corrige
  r := dietetica.responder('[{"p":"zz-prueba-001","e":0},{"p":"zz-prueba-002","e":0}]', 'estudio');
  if jsonb_array_length(r) <> 2 then raise exception 'FALLO: responder no devuelve 2 soluciones'; end if;
  if (select count(*) from dietetica.respuestas) <> 2 then raise exception 'FALLO: no se guardan las respuestas'; end if;
  if (select count(*) from dietetica.respuestas where acertada) <> 1 then raise exception 'FALLO: la corrección no es la del servidor'; end if;

  -- no da la solución de preguntas que no se le han entregado
  r := dietetica.responder('[{"p":"zz-prueba-004","e":1}]', 'estudio');
  if jsonb_array_length(r) <> 0 then raise exception 'FALLO: responder da soluciones de preguntas no entregadas'; end if;
  r := dietetica.ver_preguntas(array['zz-prueba-003', 'zz-prueba-004']);
  if jsonb_array_length(r) <> 0 then raise exception 'FALLO: ver_preguntas da preguntas no entregadas'; end if;
  r := dietetica.ver_preguntas(array['zz-prueba-001']);
  if jsonb_array_length(r) <> 1 then raise exception 'FALLO: ver_preguntas no da las ya entregadas'; end if;

  -- escribir respuestas a mano: prohibido
  begin
    insert into dietetica.respuestas (perfil_id, pregunta_id, libro, tema, acertada)
    values (dietetica.mi_perfil(), 'zz-prueba-003', 'zz-prueba', 't01', true);
    raise exception 'FALLO: A puede inventarse respuestas';
  exception when insufficient_privilege then null; end;

  -- darse saldo, alargar el acceso o hacerse admin: prohibido
  begin
    update dietetica.usuarios set saldo = 1000 where user_id = auth.uid();
    raise exception 'FALLO: A puede cambiarse el saldo';
  exception when insufficient_privilege then null; end;
  begin
    update dietetica.usuarios set acceso_hasta = now() + interval '10 years' where user_id = auth.uid();
    raise exception 'FALLO: A puede alargarse el acceso';
  exception when insufficient_privilege then null; end;
  begin
    update dietetica.usuarios set rol = 'admin' where user_id = auth.uid();
    raise exception 'FALLO: A puede hacerse administradora';
  exception when insufficient_privilege then null; end;
  begin
    insert into dietetica.movimientos (user_id, tipo, importe, saldo_despues) values (auth.uid(), 'regalo', 50, 50);
    raise exception 'FALLO: A puede apuntarse movimientos de saldo';
  exception when insufficient_privilege then null; end;

  -- sí puede cambiar su consentimiento de ofertas
  update dietetica.usuarios set acepta_ofertas = true where user_id = auth.uid();

  -- comprar sin saldo: rechazado
  begin
    perform dietetica.comprar_con_saldo('mes');
    raise exception 'FALLO: A compra sin saldo';
  exception when invalid_parameter_value then null; end;

  -- funciones de administrador: prohibidas
  begin
    perform dietetica.admin_usuarios();
    raise exception 'FALLO: A puede usar el panel de administrador';
  exception when insufficient_privilege then null; end;
  begin
    perform dietetica.admin_dar_saldo(auth.uid(), 100);
    raise exception 'FALLO: A puede darse saldo con la función de admin';
  exception when insufficient_privilege then null; end;
  begin
    perform dietetica.aplicar_compra_stripe(auth.uid(), 'curso', 'cs_falsa', 0);
    raise exception 'FALLO: A puede simular un pago de Stripe';
  exception when insufficient_privilege then null; end;

  -- guardar su propio examen: sí
  insert into dietetica.examenes (perfil_id, tipo, n_preguntas, aciertos, fallos, nota)
  values (dietetica.mi_perfil(), 'estudio', 2, 1, 1, 5);
end $$;
reset role;

-- ---------- 3. Alumna B no ve nada de A --------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000b","role":"authenticated"}', true);
do $$
declare a_perfil uuid;
begin
  perform dietetica.registrarme('Prueba B');
  if (select count(*) from dietetica.usuarios) <> 1 then raise exception 'FALLO: B ve otras cuentas'; end if;
  if (select count(*) from dietetica.perfiles) <> 1 then raise exception 'FALLO: B ve otros perfiles'; end if;
  if (select count(*) from dietetica.respuestas) <> 0 then raise exception 'FALLO: B ve respuestas de A'; end if;
  if (select count(*) from dietetica.examenes) <> 0 then raise exception 'FALLO: B ve exámenes de A'; end if;
  if (select count(*) from dietetica.progreso_temas) <> 0 then raise exception 'FALLO: B ve el progreso de A'; end if;
  -- el ranking sí muestra nombres, pero nunca emails
  if exists (select 1 from dietetica.ranking() r where r.nombre like '%@%') then raise exception 'FALLO: el ranking muestra emails'; end if;
end $$;
reset role;
-- guardar un examen en el perfil de A (con su id real): prohibido
do $$
declare a_perfil uuid := (select id from dietetica.perfiles where nombre = 'Prueba A');
begin
  perform set_config('nutritest.prueba_perfil_a', a_perfil::text, true);
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000b","role":"authenticated"}', true);
do $$ begin
  insert into dietetica.examenes (perfil_id, tipo, n_preguntas, aciertos, fallos, nota)
  values (current_setting('nutritest.prueba_perfil_a')::uuid, 'estudio', 1, 1, 0, 10);
  raise exception 'FALLO: B puede guardar exámenes en el perfil de A';
exception when insufficient_privilege then null; end $$;
reset role;

-- ---------- 4. Administrador: saldo, compra, límite, caducidad ---------
insert into dietetica.usuarios (user_id, email, nombre, rol)
values ('eeeeeeee-0000-0000-0000-00000000000c', 'prueba-admin@nutritest.test', 'Prueba Admin', 'admin');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000c","role":"authenticated"}', true);
do $$
declare lista jsonb; m jsonb;
begin
  lista := dietetica.admin_usuarios();
  if jsonb_array_length(lista) < 3 then raise exception 'FALLO: el admin no ve a todos'; end if;
  perform dietetica.admin_dar_saldo('eeeeeeee-0000-0000-0000-00000000000a', 20, 'Prueba');
  perform dietetica.admin_actualizar_usuario('eeeeeeee-0000-0000-0000-00000000000b', '{"sin_limite": true}');
  m := dietetica.admin_metricas();
  if (m->>'usuarios')::int < 3 then raise exception 'FALLO: métricas incorrectas'; end if;
  begin
    perform dietetica.admin_actualizar_usuario(auth.uid(), '{"rol": "alumno"}');
    raise exception 'FALLO: el admin puede quitarse el rol a sí mismo';
  exception when invalid_parameter_value then null; end;
  if jsonb_array_length(dietetica.admin_registro()) < 2 then raise exception 'FALLO: no queda registro de las acciones'; end if;
end $$;
reset role;

-- A compra con su saldo
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000a","role":"authenticated"}', true);
do $$
declare antes timestamptz; e jsonb;
begin
  antes := (dietetica.mi_estado()->>'acceso_hasta')::timestamptz;
  e := dietetica.comprar_con_saldo('mes');
  if (e->>'saldo')::numeric <> 15.01 then raise exception 'FALLO: el saldo tras comprar es %', e->>'saldo'; end if;
  if (e->>'acceso_hasta')::timestamptz < antes + interval '29 days' then raise exception 'FALLO: la compra no alarga el acceso'; end if;
  if (select count(*) from dietetica.movimientos) <> 2 then raise exception 'FALLO: faltan movimientos de saldo'; end if;
end $$;
reset role;

-- B sin límite: recibe todas
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000b","role":"authenticated"}', true);
do $$ begin
  if jsonb_array_length(dietetica.pedir_preguntas('[{"libro":"zz-prueba"}]')->'preguntas') <> 4 then
    raise exception 'FALLO: «sin límite» no funciona';
  end if;
end $$;
reset role;

-- B caduca: ya no recibe preguntas
update dietetica.usuarios set acceso_hasta = now() - interval '1 day' where user_id = 'eeeeeeee-0000-0000-0000-00000000000b';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000b","role":"authenticated"}', true);
do $$ begin
  if (dietetica.mi_estado()->>'tiene_acceso')::boolean then raise exception 'FALLO: B caducada sigue con acceso'; end if;
  begin
    perform dietetica.pedir_preguntas('[{"libro":"zz-prueba"}]');
    raise exception 'FALLO: una cuenta caducada recibe preguntas';
  exception when insufficient_privilege then null; end;
  begin
    insert into dietetica.examenes (perfil_id, tipo, n_preguntas, aciertos, fallos, nota)
    values (dietetica.mi_perfil(), 'estudio', 1, 1, 0, 10);
    raise exception 'FALLO: una cuenta caducada puede guardar exámenes';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- ---------- 5. Monitor Vuelos: las cuentas de NutriTest no ven nada ----
do $$
declare t text;
begin
  if to_regclass('public.vuelos_usuarios') is null then
    raise exception 'FALLO: falta ejecutar en Monitor Vuelos db/migration_014_lista_blanca_usuarios.sql';
  end if;
  -- ninguna política de Monitor Vuelos puede dejar pasar a cualquier cuenta
  select tablename into t from pg_policies
  where schemaname = 'public' and tablename <> 'vuelos_usuarios'
    and coalesce(qual, '') not like '%es_usuario_vuelos%'
  limit 1;
  if t is not null then raise exception 'FALLO: la tabla de vuelos «%» deja pasar a cuentas ajenas', t; end if;
  -- ninguna tabla de Monitor Vuelos sin RLS
  select c.relname into t from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity limit 1;
  if t is not null then raise exception 'FALLO: la tabla de vuelos «%» no tiene RLS', t; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-00000000000d","role":"authenticated"}', true);
do $$ begin
  if public.es_usuario_vuelos() then raise exception 'FALLO: una cuenta ajena cuenta como usuaria de vuelos'; end if;
  if exists (select 1 from public.prices limit 1) then raise exception 'FALLO: una cuenta ajena ve precios de vuelos'; end if;
  if exists (select 1 from public.searches limit 1) then raise exception 'FALLO: una cuenta ajena ve búsquedas de vuelos'; end if;
  begin
    insert into public.alert_profiles (owner_id, name, profile_type, origin_airports)
    values (auth.uid(), 'Intruso', 'recurrente', array['VLC']);
    raise exception 'FALLO: una cuenta ajena puede crear alertas de vuelos';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select 'TODAS LAS PRUEBAS OK' as resultado;

rollback;
