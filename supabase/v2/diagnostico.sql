-- Diagnóstico corto: quién puede escribir en dietetica.respuestas. Solo lee.
select 'permisos de authenticated' as que,
       coalesce((select string_agg(privilege_type, ', ') from information_schema.role_table_grants
                 where table_schema = 'dietetica' and table_name = 'respuestas' and grantee = 'authenticated'), 'ninguno') as resultado
union all
select 'permisos de anon',
       coalesce((select string_agg(privilege_type, ', ') from information_schema.role_table_grants
                 where table_schema = 'dietetica' and table_name = 'respuestas' and grantee = 'anon'), 'ninguno')
union all
select 'políticas',
       coalesce((select string_agg(policyname || ' (' || cmd || ')', '; ') from pg_policies
                 where schemaname = 'dietetica' and tablename = 'respuestas'), 'ninguna')
union all
select 'RLS activada', (select relrowsecurity::text from pg_class where oid = 'dietetica.respuestas'::regclass)
union all
select 'authenticated se salta RLS', (select rolbypassrls::text from pg_roles where rolname = 'authenticated')
union all
select 'authenticated es miembro de',
       coalesce((select string_agg(r2.rolname, ', ') from pg_auth_members m join pg_roles r1 on r1.oid = m.member
                 join pg_roles r2 on r2.oid = m.roleid where r1.rolname = 'authenticated'), 'nada')
union all
select 'triggers de eventos', coalesce((select string_agg(evtname, ', ') from pg_event_trigger), 'ninguno');
