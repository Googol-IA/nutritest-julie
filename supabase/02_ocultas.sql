-- =====================================================================
-- NutriTest de Julie · "No volver a mostrar esta pregunta"
-- Ejecutar una vez en Supabase → SQL Editor (después de 01_esquema.sql).
-- Se puede ejecutar varias veces sin romper nada.
-- =====================================================================

create table if not exists dietetica.ocultas (
  perfil_id    uuid not null references dietetica.perfiles(id) on delete cascade,
  pregunta_id  text not null,
  fecha        timestamptz not null default now(),
  primary key (perfil_id, pregunta_id)
);

grant select, insert, delete on dietetica.ocultas to anon, authenticated;
alter table dietetica.ocultas enable row level security;
drop policy if exists "acceso abierto" on dietetica.ocultas;
create policy "acceso abierto" on dietetica.ocultas for all to anon, authenticated using (true) with check (true);

notify pgrst, 'reload schema';
