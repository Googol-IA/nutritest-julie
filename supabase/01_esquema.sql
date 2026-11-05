-- =====================================================================
-- NutriTest de Julie · FP Superior de Dietética
-- Esquema propio "dietetica" (no toca nada de "public" ni de otros esquemas)
--
-- Cómo usarlo:
--   1. Supabase → SQL Editor → pega este archivo entero → Run.
--   2. Settings → API (Data API) → "Exposed schemas": añade  dietetica  → Save.
--   3. Copia la URL del proyecto y la clave anon/publishable a web/js/config.js
--
-- Se puede ejecutar varias veces sin romper nada.
-- =====================================================================

create schema if not exists dietetica;

-- ---------- Tablas ----------------------------------------------------

create table if not exists dietetica.perfiles (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null check (char_length(nombre) between 1 and 40),
  avatar     text not null default '🍎',
  color      text not null default '#2f9e5b',
  creado_en  timestamptz not null default now()
);

create table if not exists dietetica.respuestas (
  id           bigint generated always as identity primary key,
  perfil_id    uuid not null references dietetica.perfiles(id) on delete cascade,
  pregunta_id  text not null,
  libro        text not null,
  tema         text not null,
  acertada     boolean not null,
  modo         text not null default 'estudio',   -- estudio | aleatorio | fallos | simulacro
  fecha        timestamptz not null default now()
);
create index if not exists respuestas_perfil_fecha on dietetica.respuestas (perfil_id, fecha desc);
create index if not exists respuestas_perfil_pregunta on dietetica.respuestas (perfil_id, pregunta_id, fecha desc);

create table if not exists dietetica.examenes (
  id           bigint generated always as identity primary key,
  perfil_id    uuid not null references dietetica.perfiles(id) on delete cascade,
  tipo         text not null,                     -- estudio | aleatorio | fallos | simulacro
  libros       text not null default '',          -- ids de libros separados por coma
  n_preguntas  int  not null,
  aciertos     int  not null,
  fallos       int  not null,
  blancos      int  not null default 0,
  nota         numeric(4,2) not null,             -- sobre 10
  segundos     int  not null default 0,
  fecha        timestamptz not null default now()
);
create index if not exists examenes_perfil_fecha on dietetica.examenes (perfil_id, fecha desc);

-- ---------- Vistas ----------------------------------------------------

-- Último resultado de cada pregunta por perfil
create or replace view dietetica.estado_preguntas with (security_invoker = true) as
select distinct on (perfil_id, pregunta_id)
       perfil_id, pregunta_id, libro, tema, acertada as ultima_acertada, fecha
from dietetica.respuestas
order by perfil_id, pregunta_id, fecha desc;

-- Preguntas cuyo último intento fue un fallo ("Repasar mis fallos")
create or replace view dietetica.fallos_pendientes with (security_invoker = true) as
select perfil_id, pregunta_id, libro, tema, fecha
from dietetica.estado_preguntas
where not ultima_acertada;

-- Progreso por tema: preguntas vistas, dominadas (último intento bien) y % de acierto
create or replace view dietetica.progreso_temas with (security_invoker = true) as
select r.perfil_id, r.libro, r.tema,
       count(*)                                   as respondidas,
       count(*) filter (where r.acertada)         as aciertos,
       (select count(*) from dietetica.estado_preguntas e
         where e.perfil_id = r.perfil_id and e.libro = r.libro and e.tema = r.tema)                      as vistas,
       (select count(*) from dietetica.estado_preguntas e
         where e.perfil_id = r.perfil_id and e.libro = r.libro and e.tema = r.tema and e.ultima_acertada) as dominadas
from dietetica.respuestas r
group by r.perfil_id, r.libro, r.tema;

-- Días en que cada perfil ha estudiado (hora de España)
create or replace view dietetica.dias_estudio with (security_invoker = true) as
select perfil_id, (fecha at time zone 'Europe/Madrid')::date as dia, count(*) as respondidas
from dietetica.respuestas
group by perfil_id, (fecha at time zone 'Europe/Madrid')::date;

-- Ranking de los últimos 30 días + racha actual
create or replace view dietetica.ranking with (security_invoker = true) as
with hoy as (select (now() at time zone 'Europe/Madrid')::date as d),
grupos as (
  select perfil_id, dia,
         dia - (row_number() over (partition by perfil_id order by dia))::int as g
  from dietetica.dias_estudio
),
rachas as (
  select perfil_id, max(dia) as fin, count(*)::int as largo
  from grupos group by perfil_id, g
),
racha_actual as (
  select r.perfil_id, max(r.largo) as racha
  from rachas r, hoy
  where r.fin >= hoy.d - 1
  group by r.perfil_id
),
ultimo_mes as (
  select perfil_id,
         count(*)::int                               as respondidas,
         (count(*) filter (where acertada))::int     as aciertos
  from dietetica.respuestas
  where fecha >= now() - interval '30 days'
  group by perfil_id
)
select p.id as perfil_id, p.nombre, p.avatar, p.color,
       coalesce(u.respondidas, 0) as respondidas,
       coalesce(u.aciertos, 0)    as aciertos,
       coalesce(ra.racha, 0)      as racha
from dietetica.perfiles p
left join ultimo_mes u   on u.perfil_id = p.id
left join racha_actual ra on ra.perfil_id = p.id;

-- ---------- Permisos (sin contraseñas: acceso abierto con la clave anon) ----------

grant usage on schema dietetica to anon, authenticated;
grant select, insert, update, delete on dietetica.perfiles   to anon, authenticated;
grant select, insert                 on dietetica.respuestas to anon, authenticated;
grant select, insert                 on dietetica.examenes   to anon, authenticated;
grant delete                         on dietetica.respuestas, dietetica.examenes to anon, authenticated;
grant select on dietetica.estado_preguntas, dietetica.fallos_pendientes, dietetica.progreso_temas,
                dietetica.dias_estudio, dietetica.ranking to anon, authenticated;

alter table dietetica.perfiles   enable row level security;
alter table dietetica.respuestas enable row level security;
alter table dietetica.examenes   enable row level security;

drop policy if exists "acceso abierto" on dietetica.perfiles;
drop policy if exists "acceso abierto" on dietetica.respuestas;
drop policy if exists "acceso abierto" on dietetica.examenes;
create policy "acceso abierto" on dietetica.perfiles   for all to anon, authenticated using (true) with check (true);
create policy "acceso abierto" on dietetica.respuestas for all to anon, authenticated using (true) with check (true);
create policy "acceso abierto" on dietetica.examenes   for all to anon, authenticated using (true) with check (true);

notify pgrst, 'reload schema';
