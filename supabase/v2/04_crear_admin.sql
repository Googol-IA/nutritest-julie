-- =====================================================================
-- NutriTest · Dar de alta al administrador (Joan)
--
-- Antes: Authentication → Users → Add user → Create new user,
--        con tu email y una contraseña, y «Auto Confirm User» marcado.
--
-- Cambia EMAIL_DE_JOAN por ese email y ejecuta el archivo entero.
-- El día del cambio, 02_vincular_cuentas.sql juntará este perfil con tu
-- progreso de la web antigua.
-- =====================================================================

do $$
declare
  v_email constant text := 'EMAIL_DE_JOAN';
  v_uid uuid;
begin
  select id into v_uid from auth.users where lower(email) = lower(v_email);
  if v_uid is null then
    raise exception 'No existe la cuenta %: créala antes en Authentication → Users', v_email;
  end if;
  insert into dietetica.usuarios (user_id, email, nombre, rol, acceso_hasta, sin_limite)
  values (v_uid, lower(v_email), 'Joan', 'admin', '2100-01-01', true)
  on conflict (user_id) do update set rol = 'admin', acceso_hasta = '2100-01-01', sin_limite = true;
  insert into dietetica.perfiles (user_id, nombre, avatar, color)
  values (v_uid, 'Joan', '🍓', '#d9435e')
  on conflict (user_id) do nothing;
end $$;

-- Comprobación: debe salir una fila con rol «admin»
select u.email, u.rol, u.acceso_hasta, u.sin_limite, p.nombre as perfil
from dietetica.usuarios u left join dietetica.perfiles p on p.user_id = u.user_id;
