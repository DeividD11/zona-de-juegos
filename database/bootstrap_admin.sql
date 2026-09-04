-- Bootstrap del primer administrador.
-- EJECUTAR MANUALMENTE EN SUPABASE UNA SOLA VEZ.
-- Sustituye el correo por el del usuario que deba ser administrador.
-- Este script no se expone al navegador ni se concede como RPC.

do $$
declare
  v_target_email text := lower(trim('REEMPLAZA-ESTE-CORREO@EJEMPLO.COM'));
  v_updated integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-admin-bootstrap', 0));

  if exists (select 1 from public.app_users where role = 'admin') then
    raise exception using errcode = '42501', message = 'El bootstrap ya fue realizado: ya existe al menos un administrador.';
  end if;

  update public.app_users
  set role = 'admin'
  where email = v_target_email and is_active = true;

  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception using errcode = '22023', message = 'No se encontró un usuario activo con el correo indicado.';
  end if;
end;
$$;
