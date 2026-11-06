-- =====================================================================
-- NutriTest · Unir los perfiles migrados a sus cuentas (una sola vez)
--
-- Antes:
--   1. scripts/supabase_v2.py migrar-progreso   (copia los perfiles antiguos)
--   2. Authentication → Users → Add user → Create new user, con «Auto Confirm User»,
--      una cuenta para Joan y otra para Julie (email + contraseña).
--
-- Cambia los cuatro valores de «datos» y ejecuta el archivo entero.
-- Joan queda como administrador; Julie con acceso permanente y sin límite.
-- =====================================================================

do $$
declare
  datos constant jsonb := '[
    {"email": "EMAIL_DE_JOAN",  "perfil": "Joan",  "rol": "admin"},
    {"email": "EMAIL_DE_JULIE", "perfil": "Julie", "rol": "alumno"}
  ]';
  d jsonb;
  v_uid uuid;
  v_perfil uuid;
begin
  for d in select * from jsonb_array_elements(datos) loop
    select id into v_uid from auth.users where lower(email) = lower(d->>'email');
    if v_uid is null then
      raise exception 'No existe la cuenta %: créala antes en Authentication → Users', d->>'email';
    end if;
    select id into v_perfil from dietetica.perfiles where nombre = d->>'perfil' and user_id is null;
    if v_perfil is null then
      raise exception 'No hay un perfil migrado y libre llamado «%»', d->>'perfil';
    end if;

    insert into dietetica.usuarios (user_id, email, nombre, rol, acceso_hasta, sin_limite)
    values (v_uid, d->>'email', d->>'perfil', d->>'rol', '2100-01-01', true)
    on conflict (user_id) do update set rol = excluded.rol, acceso_hasta = excluded.acceso_hasta,
                                        sin_limite = excluded.sin_limite;
    -- Si la cuenta ya tenía un perfil nuevo (p. ej. el de 04_crear_admin.sql), lo que hizo
    -- con él pasa al perfil migrado y el nuevo se borra.
    update dietetica.respuestas set perfil_id = v_perfil
      where perfil_id in (select id from dietetica.perfiles where user_id = v_uid);
    update dietetica.examenes set perfil_id = v_perfil
      where perfil_id in (select id from dietetica.perfiles where user_id = v_uid);
    delete from dietetica.ocultas
      where perfil_id in (select id from dietetica.perfiles where user_id = v_uid);
    delete from dietetica.perfiles where user_id = v_uid;
    update dietetica.perfiles set user_id = v_uid where id = v_perfil;
    raise notice 'Unido: % → perfil «%»', d->>'email', d->>'perfil';
  end loop;
end $$;

-- Comprobación
select u.email, u.rol, u.acceso_hasta, u.sin_limite, p.nombre as perfil,
       (select count(*) from dietetica.respuestas r where r.perfil_id = p.id) as respuestas
from dietetica.usuarios u join dietetica.perfiles p on p.user_id = u.user_id;

-- Perfiles antiguos que se quedan sin cuenta (de prueba, por ejemplo): no los ve nadie.
select nombre, id from dietetica.perfiles where user_id is null;
