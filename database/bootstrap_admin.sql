-- Bootstrap del primer administrador. SOLO EJECUTAR MANUALMENTE EN SUPABASE UNA VEZ.
-- Este archivo NO se referencia desde el frontend y NO debe desplegarse como activo.
-- Sustituye los dos placeholders solo en la copia local que vas a ejecutar.
-- El correo y la clave de bootstrap se suministran EXTERNAMENTE y no se guardan.

begin;

create temporary table bootstrap_input(
  target_email text not null,
  bootstrap_secret text not null
) on commit drop;

insert into bootstrap_input values (
  'REPLACE_WITH_ADMIN_EMAIL',
  'REPLACE_WITH_RANDOM_BOOTSTRAP_SECRET_32_PLUS_CHARS'
);

do $$
declare v_email text; v_secret text; v_updated integer;
begin
  select lower(trim(target_email)), bootstrap_secret into v_email, v_secret from bootstrap_input limit 1;
  if v_email = 'replace_with_admin_email' or position('REPLACE_WITH_' in upper(v_secret)) = 1 then
    raise exception using errcode='22023', message='Debes proporcionar credenciales de bootstrap externamente antes de ejecutar este script.';
  end if;
  if char_length(v_secret) < 32 then
    raise exception using errcode='22023', message='La clave de bootstrap debe tener al menos 32 caracteres.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-admin-bootstrap',0));
  if exists(select 1 from public.app_users where role='admin' and is_active) then
    raise exception using errcode='42501', message='El bootstrap ya fue realizado: ya existe un administrador activo.';
  end if;
  update public.app_users set role='admin' where email=v_email and is_active;
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception using errcode='22023', message='No se encontró un usuario activo con el correo indicado.';
  end if;
end $$;

commit;
