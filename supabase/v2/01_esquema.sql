-- =====================================================================
-- NutriTest · Esquema v2 (cuentas, accesos con caducidad, saldo, compras)
-- Proyecto de Supabase: «Monitor Vuelos Joan» (esquema propio «dietetica»;
-- no toca «public», que es de Monitor Vuelos).
--
-- Cómo usarlo (ver supabase/v2/LEEME.md):
--   1. Antes, en Monitor Vuelos: db/migration_014_lista_blanca_usuarios.sql
--   2. SQL Editor → pega este archivo entero → Run.
--   3. Settings → API → Exposed schemas: añade  dietetica  → Save.
--   4. 99_pruebas.sql para comprobar la seguridad (no deja nada guardado).
--
-- Ideas clave de seguridad:
--   · El rol «anon» (cualquiera con la clave pública) no ve NADA de este esquema.
--   · Las preguntas no se pueden leer directamente: solo con pedir_preguntas(),
--     que comprueba el acceso y el límite diario y NO incluye la solución.
--   · Las soluciones solo salen de responder() / ver_preguntas(), y solo de
--     preguntas que ya se le entregaron a ese usuario.
--   · El saldo, las fechas de acceso y el rol solo cambian mediante funciones
--     (comprar_con_saldo, admin_*), nunca escribiendo en las tablas.
--   · La Secret Key (service_role) solo se usa en scripts y en el servidor.
-- =====================================================================

create schema if not exists dietetica;
revoke all on schema dietetica from public, anon;
grant usage on schema dietetica to authenticated, service_role;

-- Restos del esquema antiguo (supabase/01_esquema.sql, sin contraseñas): si se
-- llegó a ejecutar aquí, dejó reglas «acceso abierto» y una vista «ranking».
do $$
declare t text;
begin
  foreach t in array array['perfiles', 'respuestas', 'examenes'] loop
    if to_regclass('dietetica.' || t) is not null then
      execute format('drop policy if exists "acceso abierto" on dietetica.%I', t);
    end if;
  end loop;
end $$;
drop view if exists dietetica.ranking;

-- Permisos: al final del archivo se quitan TODOS y se dan uno a uno. Si se añade
-- una tabla o función nueva, volver a ejecutar el archivo entero (es seguro).

-- =====================================================================
-- Tablas
-- =====================================================================

-- Ajustes generales (una sola fila), editables desde Administrador
create table if not exists dietetica.ajustes (
  id                boolean primary key default true check (id),
  limite_diario     int check (limite_diario is null or limite_diario >= 0),  -- null = sin límite
  dias_demo         int not null default 2 check (dias_demo >= 0),            -- 0 = sin demo
  saldo_bienvenida  numeric(10,2) not null default 0 check (saldo_bienvenida >= 0),
  registro_abierto  boolean not null default true,
  actualizado_en    timestamptz not null default now()
);
insert into dietetica.ajustes (limite_diario, dias_demo) values (100, 2) on conflict (id) do nothing;

-- Una fila por cuenta de NutriTest (las cuentas de Monitor Vuelos no tienen fila aquí)
create table if not exists dietetica.usuarios (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  email           text not null,
  nombre          text not null check (char_length(nombre) between 1 and 40),
  rol             text not null default 'alumno' check (rol in ('alumno', 'admin')),
  acceso_hasta    timestamptz,                       -- null = nunca ha tenido acceso
  demo_usada      boolean not null default false,
  limite_diario   int check (limite_diario is null or limite_diario >= 0),  -- null = el general
  sin_limite      boolean not null default false,    -- true = ilimitado (p. ej. Julie)
  saldo           numeric(10,2) not null default 0 check (saldo >= 0),
  acepta_ofertas  boolean not null default false,    -- consentimiento para emails de ofertas
  bloqueado       boolean not null default false,
  notas           text,                              -- notas privadas del administrador
  creado_en       timestamptz not null default now(),
  ultimo_acceso   timestamptz
);

create table if not exists dietetica.perfiles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid unique references dietetica.usuarios(user_id) on delete cascade,
  nombre     text not null check (char_length(nombre) between 1 and 40),
  avatar     text not null default '🍎' check (char_length(avatar) between 1 and 8),
  color      text not null default '#2f9e5b' check (color ~ '^#[0-9a-fA-F]{6}$'),
  creado_en  timestamptz not null default now()
);

create table if not exists dietetica.preguntas (
  id              text primary key,
  libro           text not null,
  tema            text not null,               -- en «oficiales», el id del examen
  orden           int  not null,               -- posición en su archivo
  numero          int,
  pregunta        text not null,
  opciones        jsonb not null check (jsonb_typeof(opciones) = 'array'),
  correcta        smallint not null,
  explicacion     text not null default '',
  dificultad      smallint,
  orden_fijo      boolean not null default false,
  referencia      text,
  activa          boolean not null default true,
  actualizada_en  timestamptz not null default now()
);
create index if not exists preguntas_libro_tema on dietetica.preguntas (libro, tema, orden);

-- Qué preguntas se ha entregado a cada usuario y qué día (límite diario y auditoría)
create table if not exists dietetica.entregas (
  user_id      uuid not null references dietetica.usuarios(user_id) on delete cascade,
  dia          date not null,
  pregunta_id  text not null references dietetica.preguntas(id) on delete cascade,
  hora         timestamptz not null default now(),
  primary key (user_id, dia, pregunta_id)
);
create index if not exists entregas_usuario_pregunta on dietetica.entregas (user_id, pregunta_id);

create table if not exists dietetica.respuestas (
  id           bigint generated always as identity primary key,
  perfil_id    uuid not null references dietetica.perfiles(id) on delete cascade,
  pregunta_id  text not null,
  libro        text not null,
  tema         text not null,
  acertada     boolean not null,
  modo         text not null default 'estudio',
  fecha        timestamptz not null default now()
);
create index if not exists respuestas_perfil_fecha on dietetica.respuestas (perfil_id, fecha desc);
create index if not exists respuestas_perfil_pregunta on dietetica.respuestas (perfil_id, pregunta_id, fecha desc);

create table if not exists dietetica.examenes (
  id           bigint generated always as identity primary key,
  perfil_id    uuid not null references dietetica.perfiles(id) on delete cascade,
  tipo         text not null,
  libros       text not null default '',
  n_preguntas  int  not null,
  aciertos     int  not null,
  fallos       int  not null,
  blancos      int  not null default 0,
  nota         numeric(4,2) not null,
  segundos     int  not null default 0,
  detalle      jsonb,
  fecha        timestamptz not null default now()
);
create index if not exists examenes_perfil_fecha on dietetica.examenes (perfil_id, fecha desc);

create table if not exists dietetica.ocultas (
  perfil_id    uuid not null references dietetica.perfiles(id) on delete cascade,
  pregunta_id  text not null,
  fecha        timestamptz not null default now(),
  primary key (perfil_id, pregunta_id)
);

create table if not exists dietetica.planes (
  id               text primary key check (id ~ '^[a-z0-9-]+$'),
  nombre           text not null,
  descripcion      text,
  dias             int not null check (dias > 0),
  precio           numeric(10,2) not null check (precio >= 0),
  activo           boolean not null default true,
  orden            int not null default 0,
  stripe_price_id  text
);
insert into dietetica.planes (id, nombre, dias, precio, orden) values
  ('mes',       '1 mes',          30,  4.99, 1),
  ('trimestre', '3 meses',        90, 12.99, 2),
  ('curso',     'Curso completo', 300, 29.99, 3)
on conflict (id) do nothing;

create table if not exists dietetica.compras (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references dietetica.usuarios(user_id) on delete cascade,
  plan_id        text references dietetica.planes(id),
  metodo         text not null check (metodo in ('saldo', 'stripe')),
  importe        numeric(10,2) not null default 0,
  moneda         text not null default 'EUR',
  stripe_sesion  text unique,
  acceso_desde   timestamptz not null,
  acceso_hasta   timestamptz not null,
  fecha          timestamptz not null default now()
);
create index if not exists compras_fecha on dietetica.compras (fecha desc);

-- Libro de movimientos de saldo: cada cambio de saldo deja una línea
create table if not exists dietetica.movimientos (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references dietetica.usuarios(user_id) on delete cascade,
  tipo           text not null check (tipo in ('bienvenida', 'regalo', 'ajuste', 'compra')),
  importe        numeric(10,2) not null check (importe <> 0),
  saldo_despues  numeric(10,2) not null,
  concepto       text,
  compra_id      bigint references dietetica.compras(id),
  hecho_por      uuid,
  fecha          timestamptz not null default now()
);
create index if not exists movimientos_usuario on dietetica.movimientos (user_id, fecha desc);

-- Registro de todo lo que hace el administrador
create table if not exists dietetica.registro_admin (
  id        bigint generated always as identity primary key,
  admin_id  uuid not null,
  accion    text not null,
  user_id   uuid,
  detalle   jsonb,
  fecha     timestamptz not null default now()
);

-- =====================================================================
-- Funciones de apoyo (security definer: leen tablas sin depender de la RLS)
-- =====================================================================

create or replace function dietetica.hoy() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Europe/Madrid')::date;
$$;

create or replace function dietetica.es_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from dietetica.usuarios
                 where user_id = auth.uid() and rol = 'admin' and not bloqueado);
$$;

create or replace function dietetica.tiene_acceso() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from dietetica.usuarios
                 where user_id = auth.uid() and not bloqueado
                   and (rol = 'admin' or acceso_hasta > now()));
$$;

create or replace function dietetica.mi_perfil() returns uuid
language sql stable security definer set search_path = '' as $$
  select id from dietetica.perfiles where user_id = auth.uid();
$$;

-- Límite diario efectivo de un usuario (null = sin límite)
create or replace function dietetica.limite_de(p_user uuid) returns int
language sql stable security definer set search_path = '' as $$
  select case when u.rol = 'admin' or u.sin_limite then null
              else coalesce(u.limite_diario, a.limite_diario) end
  from dietetica.usuarios u cross join dietetica.ajustes a
  where u.user_id = p_user;
$$;

create or replace function dietetica.exigir_admin() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not dietetica.es_admin() then
    raise exception 'Solo para administradores' using errcode = '42501';
  end if;
end $$;

-- =====================================================================
-- Funciones para la app (usuario con sesión)
-- =====================================================================

-- Estado de la cuenta: lo primero que pide la app al entrar
create or replace function dietetica.mi_estado() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u dietetica.usuarios;
  v_limite int;
  v_usadas int;
begin
  select * into u from dietetica.usuarios where user_id = auth.uid();
  if not found then
    return jsonb_build_object('registrado', false);
  end if;
  update dietetica.usuarios set ultimo_acceso = now() where user_id = u.user_id;
  v_limite := dietetica.limite_de(u.user_id);
  select count(*) into v_usadas from dietetica.entregas where user_id = u.user_id and dia = dietetica.hoy();
  return jsonb_build_object(
    'registrado', true,
    'nombre', u.nombre,
    'email', u.email,
    'rol', u.rol,
    'acceso_hasta', u.acceso_hasta,
    'tiene_acceso', dietetica.tiene_acceso(),
    'bloqueado', u.bloqueado,
    'demo_usada', u.demo_usada,
    'saldo', u.saldo,
    'acepta_ofertas', u.acepta_ofertas,
    'limite_diario', v_limite,
    'usadas_hoy', v_usadas,
    'perfil', (select to_jsonb(p) from dietetica.perfiles p where p.user_id = u.user_id)
  );
end $$;

-- Alta en NutriTest de una cuenta recién creada (crea usuario + perfil y da la demo)
create or replace function dietetica.registrarme(
  p_nombre text, p_avatar text default '🍎', p_color text default '#2f9e5b',
  p_acepta_ofertas boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  a dietetica.ajustes;
begin
  if v_uid is null then
    raise exception 'Hay que iniciar sesión' using errcode = '28000';
  end if;
  if exists (select 1 from dietetica.usuarios where user_id = v_uid) then
    return dietetica.mi_estado();
  end if;
  select * into a from dietetica.ajustes;
  if not a.registro_abierto then
    raise exception 'El registro está cerrado' using errcode = '42501';
  end if;
  insert into dietetica.usuarios (user_id, email, nombre, acceso_hasta, demo_usada, saldo, acepta_ofertas)
  select v_uid, au.email, trim(p_nombre),
         case when a.dias_demo > 0 then now() + make_interval(days => a.dias_demo) end,
         a.dias_demo > 0, a.saldo_bienvenida, coalesce(p_acepta_ofertas, false)
  from auth.users au where au.id = v_uid;
  if a.saldo_bienvenida > 0 then
    insert into dietetica.movimientos (user_id, tipo, importe, saldo_despues, concepto)
    values (v_uid, 'bienvenida', a.saldo_bienvenida, a.saldo_bienvenida, 'Saldo de bienvenida');
  end if;
  insert into dietetica.perfiles (user_id, nombre, avatar, color)
  values (v_uid, trim(p_nombre), coalesce(p_avatar, '🍎'), coalesce(p_color, '#2f9e5b'));
  return dietetica.mi_estado();
end $$;

-- Preguntas para un test, SIN solución.
--   p_temas: [{"libro":"dietoterapia","tema":"t01"}, {"libro":"oficiales"}]  (sin tema = libro entero)
--   p_ids:   lista de ids concretos (repasar fallos)
--   p_n:     cuántas (null = todas);  p_aleatorio: false = en el orden del archivo
-- Las preguntas ya entregadas hoy no vuelven a contar para el límite diario.
create or replace function dietetica.pedir_preguntas(
  p_temas jsonb default null, p_ids text[] default null, p_n int default null,
  p_aleatorio boolean default true, p_excluir_ocultas boolean default true
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_perfil uuid;
  v_limite int;
  v_restantes int;
  v_hoy date := dietetica.hoy();
  v_res jsonb;
begin
  if not dietetica.tiene_acceso() then
    raise exception 'Tu acceso ha caducado' using errcode = '42501', hint = 'sin_acceso';
  end if;
  if p_n is not null and p_n < 1 then p_n := null; end if;
  v_perfil := dietetica.mi_perfil();
  v_limite := dietetica.limite_de(v_uid);
  if v_limite is not null then
    select greatest(v_limite - count(*), 0) into v_restantes
    from dietetica.entregas where user_id = v_uid and dia = v_hoy;
  end if;

  with candidatas as (
    select q.id, q.libro, q.tema, q.orden,
           exists (select 1 from dietetica.entregas e
                   where e.user_id = v_uid and e.dia = v_hoy and e.pregunta_id = q.id) as ya_hoy
    from dietetica.preguntas q
    where q.activa
      and ((p_ids is not null and q.id = any (p_ids))
           or (p_temas is not null and exists (
                 select 1 from jsonb_to_recordset(p_temas) as t(libro text, tema text)
                 where t.libro = q.libro and (t.tema is null or t.tema = q.tema))))
      and (not p_excluir_ocultas or not exists (
                 select 1 from dietetica.ocultas o where o.perfil_id = v_perfil and o.pregunta_id = q.id))
  ),
  ordenadas as (
    select c.*, row_number() over (
             order by case when p_aleatorio then random() else 0 end, c.libro, c.tema, c.orden) as rn
    from candidatas c
  ),
  elegidas as (
    select o.*, sum(case when o.ya_hoy then 0 else 1 end) over (order by o.rn) as nuevas_acum
    from ordenadas o
    where p_n is null or o.rn <= p_n
  ),
  finales as (
    select * from elegidas where ya_hoy or v_restantes is null or nuevas_acum <= v_restantes
  ),
  apuntadas as (
    insert into dietetica.entregas (user_id, dia, pregunta_id)
    select v_uid, v_hoy, f.id from finales f where not f.ya_hoy
    on conflict do nothing
    returning 1
  )
  select jsonb_build_object(
    'preguntas', coalesce((
       select jsonb_agg(jsonb_build_object(
                'id', q.id, 'libro', q.libro, 'tema', q.tema, 'numero', q.numero,
                'pregunta', q.pregunta, 'opciones', q.opciones, 'orden_fijo', q.orden_fijo,
                'dificultad', q.dificultad, 'referencia', q.referencia) order by f.rn)
       from finales f join dietetica.preguntas q on q.id = f.id), '[]'::jsonb),
    'cortado', (select count(*) from elegidas) > (select count(*) from finales),
    'nuevas', (select count(*) from apuntadas),
    'limite_diario', v_limite
  ) into v_res;

  if v_limite is not null then
    v_res := v_res || jsonb_build_object('restantes_hoy', greatest(v_restantes - (v_res->>'nuevas')::int, 0));
  end if;
  return v_res;
end $$;

-- Guarda respuestas y devuelve la solución. La corrección la hace el servidor.
--   p_items: [{"p":"ae-t01-001","e":2}, {"p":"ae-t01-002","e":null}]  (e = índice original; null = en blanco)
create or replace function dietetica.responder(p_items jsonb, p_modo text default 'estudio') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_perfil uuid;
  v_res jsonb;
begin
  if not dietetica.tiene_acceso() then
    raise exception 'Tu acceso ha caducado' using errcode = '42501', hint = 'sin_acceso';
  end if;
  if char_length(coalesce(p_modo, '')) not between 1 and 20 then
    raise exception 'Modo no válido' using errcode = '22023';
  end if;
  v_perfil := dietetica.mi_perfil();

  with items as (
    select distinct on (x.p) x.p as pregunta_id, x.e as elegida
    from jsonb_to_recordset(p_items) as x(p text, e int)
  ),
  validas as (
    select i.pregunta_id, i.elegida, q.correcta, q.explicacion, q.libro, q.tema
    from items i
    join dietetica.preguntas q on q.id = i.pregunta_id
    where exists (select 1 from dietetica.entregas en
                  where en.user_id = v_uid and en.pregunta_id = i.pregunta_id)
  ),
  guardadas as (
    insert into dietetica.respuestas (perfil_id, pregunta_id, libro, tema, acertada, modo)
    select v_perfil, v.pregunta_id, v.libro, v.tema, v.elegida = v.correcta, p_modo
    from validas v where v.elegida is not null
    returning 1
  )
  -- (el insert de «guardadas» se ejecuta siempre, aunque no se lea su resultado)
  select coalesce(jsonb_agg(jsonb_build_object(
           'p', v.pregunta_id, 'correcta', v.correcta, 'explicacion', v.explicacion,
           'acertada', case when v.elegida is null then null else v.elegida = v.correcta end)), '[]'::jsonb)
  into v_res
  from validas v;
  return v_res;
end $$;

-- Preguntas completas (con solución) que ya se le entregaron a este usuario:
-- para el historial de tests y la lista de preguntas ocultas.
create or replace function dietetica.ver_preguntas(p_ids text[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not dietetica.tiene_acceso() then
    raise exception 'Tu acceso ha caducado' using errcode = '42501', hint = 'sin_acceso';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', q.id, 'libro', q.libro, 'tema', q.tema, 'numero', q.numero,
             'pregunta', q.pregunta, 'opciones', q.opciones, 'correcta', q.correcta,
             'explicacion', q.explicacion, 'orden_fijo', q.orden_fijo,
             'dificultad', q.dificultad, 'referencia', q.referencia))
    from dietetica.preguntas q
    where q.id = any (p_ids)
      and exists (select 1 from dietetica.entregas en
                  where en.user_id = auth.uid() and en.pregunta_id = q.id)), '[]'::jsonb);
end $$;

-- Ranking de los últimos 30 días + racha (solo nombre y avatar, nunca el email)
create or replace function dietetica.ranking()
returns table (perfil_id uuid, nombre text, avatar text, color text, respondidas int, aciertos int, racha int)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if not dietetica.tiene_acceso() then
    raise exception 'Tu acceso ha caducado' using errcode = '42501', hint = 'sin_acceso';
  end if;
  return query
  with dias as (
    select r.perfil_id, (r.fecha at time zone 'Europe/Madrid')::date as dia
    from dietetica.respuestas r group by 1, 2
  ),
  grupos as (
    select d.perfil_id, d.dia, d.dia - (row_number() over (partition by d.perfil_id order by d.dia))::int as g
    from dias d
  ),
  rachas as (
    select g.perfil_id, max(g.dia) as fin, count(*)::int as largo from grupos g group by g.perfil_id, g.g
  ),
  racha_actual as (
    select r.perfil_id, max(r.largo) as racha from rachas r
    where r.fin >= dietetica.hoy() - 1 group by r.perfil_id
  ),
  ultimo_mes as (
    select r.perfil_id, count(*)::int as respondidas, (count(*) filter (where r.acertada))::int as aciertos
    from dietetica.respuestas r where r.fecha >= now() - interval '30 days' group by r.perfil_id
  )
  select p.id, p.nombre, p.avatar, p.color,
         coalesce(um.respondidas, 0), coalesce(um.aciertos, 0), coalesce(ra.racha, 0)
  from dietetica.perfiles p
  join dietetica.usuarios u on u.user_id = p.user_id and not u.bloqueado
  left join ultimo_mes um on um.perfil_id = p.id
  left join racha_actual ra on ra.perfil_id = p.id;
end $$;

-- Comprar un plan con el saldo ficticio
create or replace function dietetica.comprar_con_saldo(p_plan text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  u dietetica.usuarios;
  pl dietetica.planes;
  v_desde timestamptz;
  v_hasta timestamptz;
  v_compra bigint;
begin
  select * into pl from dietetica.planes where id = p_plan and activo;
  if not found then raise exception 'Ese plan no existe' using errcode = '22023'; end if;
  select * into u from dietetica.usuarios where user_id = v_uid for update;
  if not found then raise exception 'Hay que registrarse primero' using errcode = '42501'; end if;
  if u.bloqueado then raise exception 'Cuenta bloqueada' using errcode = '42501'; end if;
  if u.saldo < pl.precio then raise exception 'Saldo insuficiente' using errcode = '22023', hint = 'saldo'; end if;

  v_desde := greatest(now(), coalesce(u.acceso_hasta, now()));
  v_hasta := v_desde + make_interval(days => pl.dias);
  update dietetica.usuarios set saldo = saldo - pl.precio, acceso_hasta = v_hasta where user_id = v_uid;
  insert into dietetica.compras (user_id, plan_id, metodo, importe, acceso_desde, acceso_hasta)
  values (v_uid, pl.id, 'saldo', pl.precio, v_desde, v_hasta) returning id into v_compra;
  if pl.precio > 0 then
    insert into dietetica.movimientos (user_id, tipo, importe, saldo_despues, concepto, compra_id)
    values (v_uid, 'compra', -pl.precio, u.saldo - pl.precio, 'Compra: ' || pl.nombre, v_compra);
  end if;
  return dietetica.mi_estado();
end $$;

-- Pagos con Stripe (fase 3): solo lo llama el servidor con la Secret Key.
-- Si Stripe avisa dos veces del mismo pago, la segunda no hace nada.
create or replace function dietetica.aplicar_compra_stripe(
  p_user uuid, p_plan text, p_sesion text, p_importe numeric, p_moneda text default 'EUR'
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u dietetica.usuarios;
  pl dietetica.planes;
  v_desde timestamptz;
  v_hasta timestamptz;
begin
  if exists (select 1 from dietetica.compras where stripe_sesion = p_sesion) then
    return jsonb_build_object('ok', true, 'repetida', true);
  end if;
  select * into pl from dietetica.planes where id = p_plan;
  if not found then raise exception 'Ese plan no existe'; end if;
  select * into u from dietetica.usuarios where user_id = p_user for update;
  if not found then raise exception 'Usuario desconocido'; end if;
  v_desde := greatest(now(), coalesce(u.acceso_hasta, now()));
  v_hasta := v_desde + make_interval(days => pl.dias);
  update dietetica.usuarios set acceso_hasta = v_hasta where user_id = p_user;
  insert into dietetica.compras (user_id, plan_id, metodo, importe, moneda, stripe_sesion, acceso_desde, acceso_hasta)
  values (p_user, pl.id, 'stripe', p_importe, upper(p_moneda), p_sesion, v_desde, v_hasta);
  return jsonb_build_object('ok', true, 'acceso_hasta', v_hasta);
end $$;

-- =====================================================================
-- Funciones de Administrador (todas comprueban el rol y quedan registradas)
-- =====================================================================

create or replace function dietetica.admin_usuarios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform dietetica.exigir_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'user_id', u.user_id, 'email', u.email, 'nombre', u.nombre, 'rol', u.rol,
             'acceso_hasta', u.acceso_hasta,
             'tiene_acceso', not u.bloqueado and (u.rol = 'admin' or u.acceso_hasta > now()),
             'demo_usada', u.demo_usada, 'bloqueado', u.bloqueado, 'saldo', u.saldo,
             'limite_diario', u.limite_diario, 'sin_limite', u.sin_limite,
             'limite_efectivo', dietetica.limite_de(u.user_id),
             'usadas_hoy', (select count(*) from dietetica.entregas e
                            where e.user_id = u.user_id and e.dia = dietetica.hoy()),
             'respondidas_30d', (select count(*) from dietetica.respuestas r
                                 join dietetica.perfiles p on p.id = r.perfil_id
                                 where p.user_id = u.user_id and r.fecha >= now() - interval '30 days'),
             'compras', (select count(*) from dietetica.compras c where c.user_id = u.user_id),
             'acepta_ofertas', u.acepta_ofertas, 'notas', u.notas,
             'creado_en', u.creado_en, 'ultimo_acceso', u.ultimo_acceso)
           order by u.creado_en desc)
    from dietetica.usuarios u), '[]'::jsonb);
end $$;

-- p_cambios admite: acceso_hasta, limite_diario, sin_limite, bloqueado, rol, notas, nombre
-- (una clave con valor null lo deja vacío; una clave que no aparece no se toca)
create or replace function dietetica.admin_actualizar_usuario(p_user uuid, p_cambios jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c jsonb := coalesce(p_cambios, '{}'::jsonb);
begin
  perform dietetica.exigir_admin();
  if p_user = auth.uid() and ((c ? 'rol' and c->>'rol' is distinct from 'admin')
                              or coalesce((c->>'bloqueado')::boolean, false)) then
    raise exception 'No puedes quitarte el rol de administrador ni bloquearte' using errcode = '22023';
  end if;
  update dietetica.usuarios set
    acceso_hasta  = case when c ? 'acceso_hasta'  then (c->>'acceso_hasta')::timestamptz else acceso_hasta end,
    limite_diario = case when c ? 'limite_diario' then (c->>'limite_diario')::int else limite_diario end,
    sin_limite    = case when c ? 'sin_limite'    then coalesce((c->>'sin_limite')::boolean, false) else sin_limite end,
    bloqueado     = case when c ? 'bloqueado'     then coalesce((c->>'bloqueado')::boolean, false) else bloqueado end,
    rol           = case when c ? 'rol'           then c->>'rol' else rol end,
    notas         = case when c ? 'notas'         then c->>'notas' else notas end,
    nombre        = case when c ? 'nombre'        then c->>'nombre' else nombre end
  where user_id = p_user;
  if not found then raise exception 'Usuario desconocido' using errcode = '22023'; end if;
  insert into dietetica.registro_admin (admin_id, accion, user_id, detalle)
  values (auth.uid(), 'actualizar_usuario', p_user, c);
  return dietetica.admin_usuarios();
end $$;

-- Dar (o quitar, con importe negativo) saldo ficticio
create or replace function dietetica.admin_dar_saldo(p_user uuid, p_importe numeric, p_concepto text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_saldo numeric(10,2);
begin
  perform dietetica.exigir_admin();
  if p_importe is null or p_importe = 0 then raise exception 'Importe no válido' using errcode = '22023'; end if;
  update dietetica.usuarios set saldo = saldo + p_importe where user_id = p_user returning saldo into v_saldo;
  if not found then raise exception 'Usuario desconocido' using errcode = '22023'; end if;
  insert into dietetica.movimientos (user_id, tipo, importe, saldo_despues, concepto, hecho_por)
  values (p_user, case when p_importe > 0 then 'regalo' else 'ajuste' end, p_importe, v_saldo,
          coalesce(p_concepto, case when p_importe > 0 then 'Regalo del administrador' else 'Ajuste del administrador' end),
          auth.uid());
  insert into dietetica.registro_admin (admin_id, accion, user_id, detalle)
  values (auth.uid(), 'dar_saldo', p_user, jsonb_build_object('importe', p_importe, 'concepto', p_concepto));
  return jsonb_build_object('saldo', v_saldo);
end $$;

-- p_cambios admite: limite_diario (null = sin límite), dias_demo, saldo_bienvenida, registro_abierto
create or replace function dietetica.admin_ajustes(p_cambios jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c jsonb := coalesce(p_cambios, '{}'::jsonb);
begin
  perform dietetica.exigir_admin();
  if c <> '{}'::jsonb then
    update dietetica.ajustes set
      limite_diario    = case when c ? 'limite_diario'    then (c->>'limite_diario')::int else limite_diario end,
      dias_demo        = case when c ? 'dias_demo'        then (c->>'dias_demo')::int else dias_demo end,
      saldo_bienvenida = case when c ? 'saldo_bienvenida' then (c->>'saldo_bienvenida')::numeric else saldo_bienvenida end,
      registro_abierto = case when c ? 'registro_abierto' then (c->>'registro_abierto')::boolean else registro_abierto end,
      actualizado_en   = now();
    insert into dietetica.registro_admin (admin_id, accion, detalle) values (auth.uid(), 'ajustes', c);
  end if;
  return (select to_jsonb(a) from dietetica.ajustes a);
end $$;

-- Crear o cambiar un plan: {"id":"mes","nombre":"1 mes","dias":30,"precio":4.99,"activo":true,"orden":1}
create or replace function dietetica.admin_guardar_plan(p_plan jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform dietetica.exigir_admin();
  insert into dietetica.planes (id, nombre, descripcion, dias, precio, activo, orden, stripe_price_id)
  values (p_plan->>'id', p_plan->>'nombre', p_plan->>'descripcion', (p_plan->>'dias')::int,
          (p_plan->>'precio')::numeric, coalesce((p_plan->>'activo')::boolean, true),
          coalesce((p_plan->>'orden')::int, 0), p_plan->>'stripe_price_id')
  on conflict (id) do update set
    nombre = excluded.nombre, descripcion = excluded.descripcion, dias = excluded.dias,
    precio = excluded.precio, activo = excluded.activo, orden = excluded.orden,
    stripe_price_id = excluded.stripe_price_id;
  insert into dietetica.registro_admin (admin_id, accion, detalle) values (auth.uid(), 'guardar_plan', p_plan);
  return coalesce((select jsonb_agg(to_jsonb(p) order by p.orden) from dietetica.planes p), '[]'::jsonb);
end $$;

-- Métricas para el panel
create or replace function dietetica.admin_metricas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  perform dietetica.exigir_admin();
  select jsonb_build_object(
    'usuarios', (select count(*) from dietetica.usuarios),
    'con_acceso', (select count(*) from dietetica.usuarios
                   where not bloqueado and (rol = 'admin' or acceso_hasta > now())),
    'en_demo', (select count(*) from dietetica.usuarios u where u.demo_usada and u.acceso_hasta > now()
                and not exists (select 1 from dietetica.compras c where c.user_id = u.user_id)),
    'caducados', (select count(*) from dietetica.usuarios
                  where rol <> 'admin' and acceso_hasta <= now()),
    'sin_acceso_nunca', (select count(*) from dietetica.usuarios where rol <> 'admin' and acceso_hasta is null),
    'caducan_7_dias', (select count(*) from dietetica.usuarios
                       where acceso_hasta > now() and acceso_hasta <= now() + interval '7 days'),
    'nuevos_7_dias', (select count(*) from dietetica.usuarios where creado_en >= now() - interval '7 days'),
    'activos_7_dias', (select count(*) from dietetica.usuarios where ultimo_acceso >= now() - interval '7 days'),
    'demos_total', (select count(*) from dietetica.usuarios where demo_usada),
    'demos_que_compran', (select count(*) from dietetica.usuarios u where u.demo_usada
                          and exists (select 1 from dietetica.compras c where c.user_id = u.user_id)),
    'ingresos_total', (select coalesce(sum(importe), 0) from dietetica.compras),
    'ingresos_saldo', (select coalesce(sum(importe), 0) from dietetica.compras where metodo = 'saldo'),
    'ingresos_stripe', (select coalesce(sum(importe), 0) from dietetica.compras where metodo = 'stripe'),
    'ingresos_30_dias', (select coalesce(sum(importe), 0) from dietetica.compras where fecha >= now() - interval '30 days'),
    'compras_30_dias', (select count(*) from dietetica.compras where fecha >= now() - interval '30 days'),
    'saldo_regalado', (select coalesce(sum(importe), 0) from dietetica.movimientos where tipo in ('regalo', 'bienvenida')),
    'saldo_pendiente', (select coalesce(sum(saldo), 0) from dietetica.usuarios),
    'respuestas_hoy', (select count(*) from dietetica.respuestas
                       where (fecha at time zone 'Europe/Madrid')::date = dietetica.hoy()),
    'respuestas_7_dias', (select count(*) from dietetica.respuestas where fecha >= now() - interval '7 days'),
    'por_plan', coalesce((select jsonb_agg(jsonb_build_object('plan', x.plan_id, 'compras', x.n, 'ingresos', x.total))
                          from (select plan_id, count(*) as n, sum(importe) as total
                                from dietetica.compras group by plan_id) x), '[]'::jsonb),
    'ingresos_por_mes', coalesce((select jsonb_agg(jsonb_build_object('mes', x.mes, 'ingresos', x.total) order by x.mes)
                          from (select to_char(fecha at time zone 'Europe/Madrid', 'YYYY-MM') as mes, sum(importe) as total
                                from dietetica.compras group by 1) x), '[]'::jsonb)
  ) into v;
  return v;
end $$;

create or replace function dietetica.admin_registro(p_limite int default 100) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform dietetica.exigir_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.fecha desc)
    from (select r.fecha, r.accion, r.detalle, u.email as usuario, a.email as admin
          from dietetica.registro_admin r
          left join dietetica.usuarios u on u.user_id = r.user_id
          left join dietetica.usuarios a on a.user_id = r.admin_id
          order by r.fecha desc limit least(coalesce(p_limite, 100), 1000)) x), '[]'::jsonb);
end $$;

-- =====================================================================
-- Vistas de progreso (respetan la RLS de respuestas: cada uno ve lo suyo)
-- =====================================================================

create or replace view dietetica.estado_preguntas with (security_invoker = true) as
select distinct on (perfil_id, pregunta_id)
       perfil_id, pregunta_id, libro, tema, acertada as ultima_acertada, fecha
from dietetica.respuestas
order by perfil_id, pregunta_id, fecha desc;

create or replace view dietetica.fallos_pendientes with (security_invoker = true) as
select perfil_id, pregunta_id, libro, tema, fecha
from dietetica.estado_preguntas
where not ultima_acertada;

create or replace view dietetica.progreso_temas with (security_invoker = true) as
select r.perfil_id, r.libro, r.tema,
       count(*)                           as respondidas,
       count(*) filter (where r.acertada) as aciertos,
       (select count(*) from dietetica.estado_preguntas e
         where e.perfil_id = r.perfil_id and e.libro = r.libro and e.tema = r.tema)                      as vistas,
       (select count(*) from dietetica.estado_preguntas e
         where e.perfil_id = r.perfil_id and e.libro = r.libro and e.tema = r.tema and e.ultima_acertada) as dominadas
from dietetica.respuestas r
group by r.perfil_id, r.libro, r.tema;

create or replace view dietetica.dias_estudio with (security_invoker = true) as
select perfil_id, (fecha at time zone 'Europe/Madrid')::date as dia, count(*) as respondidas
from dietetica.respuestas
group by perfil_id, (fecha at time zone 'Europe/Madrid')::date;

-- =====================================================================
-- Seguridad de filas (RLS) y permisos
-- =====================================================================

alter table dietetica.ajustes        enable row level security;
alter table dietetica.usuarios       enable row level security;
alter table dietetica.perfiles       enable row level security;
alter table dietetica.preguntas      enable row level security;
alter table dietetica.entregas       enable row level security;
alter table dietetica.respuestas     enable row level security;
alter table dietetica.examenes       enable row level security;
alter table dietetica.ocultas        enable row level security;
alter table dietetica.planes         enable row level security;
alter table dietetica.compras        enable row level security;
alter table dietetica.movimientos    enable row level security;
alter table dietetica.registro_admin enable row level security;

-- Empezar de cero: nadie salvo service_role tiene nada
revoke all on all tables in schema dietetica from public, anon, authenticated;
revoke execute on all functions in schema dietetica from public, anon, authenticated;
grant all on all tables in schema dietetica to service_role;
grant usage, select on all sequences in schema dietetica to service_role;
grant execute on all functions in schema dietetica to service_role;

-- usuarios: cada uno ve su fila; solo puede cambiar su consentimiento de ofertas
grant select on dietetica.usuarios to authenticated;
grant update (acepta_ofertas) on dietetica.usuarios to authenticated;
drop policy if exists "ver la propia cuenta" on dietetica.usuarios;
create policy "ver la propia cuenta" on dietetica.usuarios for select to authenticated
  using (user_id = (select auth.uid()) or (select dietetica.es_admin()));
drop policy if exists "cambiar la propia cuenta" on dietetica.usuarios;
create policy "cambiar la propia cuenta" on dietetica.usuarios for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- perfiles: el propio (nombre, avatar y color editables)
grant select on dietetica.perfiles to authenticated;
grant update (nombre, avatar, color) on dietetica.perfiles to authenticated;
drop policy if exists "ver el propio perfil" on dietetica.perfiles;
create policy "ver el propio perfil" on dietetica.perfiles for select to authenticated
  using (user_id = (select auth.uid()) or (select dietetica.es_admin()));
drop policy if exists "cambiar el propio perfil" on dietetica.perfiles;
create policy "cambiar el propio perfil" on dietetica.perfiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- respuestas: solo lectura de las propias (se escriben con responder())
grant select on dietetica.respuestas to authenticated;
drop policy if exists "ver las propias respuestas" on dietetica.respuestas;
create policy "ver las propias respuestas" on dietetica.respuestas for select to authenticated
  using (perfil_id = (select dietetica.mi_perfil()) or (select dietetica.es_admin()));

-- examenes: leer y guardar los propios
grant select, insert on dietetica.examenes to authenticated;
grant usage on sequence dietetica.examenes_id_seq to authenticated;
drop policy if exists "ver los propios examenes" on dietetica.examenes;
create policy "ver los propios examenes" on dietetica.examenes for select to authenticated
  using (perfil_id = (select dietetica.mi_perfil()) or (select dietetica.es_admin()));
drop policy if exists "guardar los propios examenes" on dietetica.examenes;
create policy "guardar los propios examenes" on dietetica.examenes for insert to authenticated
  with check (perfil_id = (select dietetica.mi_perfil()) and (select dietetica.tiene_acceso()));

-- ocultas: las propias
grant select, insert, delete on dietetica.ocultas to authenticated;
drop policy if exists "las propias ocultas" on dietetica.ocultas;
create policy "las propias ocultas" on dietetica.ocultas for all to authenticated
  using (perfil_id = (select dietetica.mi_perfil())) with check (perfil_id = (select dietetica.mi_perfil()));

-- planes: los activos, para la tienda
grant select on dietetica.planes to authenticated;
drop policy if exists "ver planes activos" on dietetica.planes;
create policy "ver planes activos" on dietetica.planes for select to authenticated
  using (activo or (select dietetica.es_admin()));

-- compras y movimientos: los propios
grant select on dietetica.compras, dietetica.movimientos to authenticated;
drop policy if exists "ver las propias compras" on dietetica.compras;
create policy "ver las propias compras" on dietetica.compras for select to authenticated
  using (user_id = (select auth.uid()) or (select dietetica.es_admin()));
drop policy if exists "ver los propios movimientos" on dietetica.movimientos;
create policy "ver los propios movimientos" on dietetica.movimientos for select to authenticated
  using (user_id = (select auth.uid()) or (select dietetica.es_admin()));

-- ajustes: la app necesita saber los días de demo y si el registro está abierto
grant select on dietetica.ajustes to authenticated;
drop policy if exists "leer ajustes" on dietetica.ajustes;
create policy "leer ajustes" on dietetica.ajustes for select to authenticated using (true);

-- preguntas, entregas y registro_admin: sin permisos para nadie (solo por funciones)

-- vistas de progreso
grant select on dietetica.estado_preguntas, dietetica.fallos_pendientes,
                dietetica.progreso_temas, dietetica.dias_estudio to authenticated;

-- funciones que puede llamar la app
grant execute on function
  dietetica.mi_estado(),
  dietetica.registrarme(text, text, text, boolean),
  dietetica.pedir_preguntas(jsonb, text[], int, boolean, boolean),
  dietetica.responder(jsonb, text),
  dietetica.ver_preguntas(text[]),
  dietetica.ranking(),
  dietetica.comprar_con_saldo(text),
  dietetica.admin_usuarios(),
  dietetica.admin_actualizar_usuario(uuid, jsonb),
  dietetica.admin_dar_saldo(uuid, numeric, text),
  dietetica.admin_ajustes(jsonb),
  dietetica.admin_guardar_plan(jsonb),
  dietetica.admin_metricas(),
  dietetica.admin_registro(int)
to authenticated;
-- las de apoyo las usan las políticas RLS, así que también deben poder ejecutarse
grant execute on function dietetica.es_admin(), dietetica.tiene_acceso(), dietetica.mi_perfil(),
  dietetica.hoy() to authenticated;
-- aplicar_compra_stripe y limite_de/exigir_admin: solo service_role (y las otras funciones por dentro)

notify pgrst, 'reload schema';
