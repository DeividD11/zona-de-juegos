-- Recuperación manual sin añadir un backend de correo.
-- EJECUTAR SOLO EN EL SQL EDITOR DE SUPABASE POR UN OPERADOR AUTORIZADO.
-- Sustituye el correo y entrega el enlace resultante por un canal privado.

do $$
declare
  v_email text := lower(trim('REEMPLAZA-ESTE-CORREO@EJEMPLO.COM'));
  v_user public.app_users;
  v_token text;
  v_base_url text := 'https://TU-DOMINIO/reset-password.html?token=';
begin
  select * into v_user from public.app_users where email = v_email and is_active = true limit 1;
  if not found then
    raise exception using errcode = '22023', message = 'No se encontró una cuenta activa con ese correo.';
  end if;

  delete from public.password_reset_tokens where user_id = v_user.id and used_at is null;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.password_reset_tokens(user_id, token_hash, expires_at)
  values (v_user.id, extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), now() + interval '30 minutes');

  raise notice 'ENLACE DE RECUPERACIÓN (válido 30 minutos): %', v_base_url || v_token;
end;
$$;
