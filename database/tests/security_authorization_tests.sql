-- Suite de seguridad SQL para ejecutar en STAGING.
-- Requiere dos cuentas de prueba: una USER y una ADMIN.
-- Nunca usar credenciales reales de producción.
--
-- Sustituye los marcadores antes de ejecutar:
--   <USER_SESSION_TOKEN>
--   <ADMIN_SESSION_TOKEN>
--   <OTHER_USER_ID>
--   <GAME_ID>

begin;

-- USER no debe poder cambiar roles.
do $$
begin
  begin
    perform public.admin_set_user_role('<USER_SESSION_TOKEN>', '<OTHER_USER_ID>'::uuid, 'admin');
    raise exception 'TEST FAIL: USER pudo ejecutar admin_set_user_role';
  exception when others then
    if sqlerrm not like '%Administrador%' and sqlstate <> '42501' then
      raise;
    end if;
  end;
end;
$$;

-- USER no debe poder cambiar el estado de un juego.
do $$
begin
  begin
    perform public.admin_set_game_active('<USER_SESSION_TOKEN>', '<GAME_ID>'::uuid, false);
    raise exception 'TEST FAIL: USER pudo ejecutar admin_set_game_active';
  exception when others then
    if sqlerrm not like '%Administrador%' and sqlstate <> '42501' then
      raise;
    end if;
  end;
end;
$$;

-- USER no debe poder leer páginas administrativas.
do $$
begin
  begin
    perform public.admin_list_users_page('<USER_SESSION_TOKEN>', 1, 20);
    raise exception 'TEST FAIL: USER pudo listar usuarios';
  exception when others then
    if sqlerrm not like '%Administrador%' and sqlstate <> '42501' then
      raise;
    end if;
  end;
end;
$$;

-- ADMIN sí puede utilizar el endpoint administrativo.
select public.admin_list_users_page('<ADMIN_SESSION_TOKEN>', 1, 1);

rollback;


-- Contract checks: these should return rows only when the deployment is configured correctly.
select n.nspname as schema_name, p.proname as function_name, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'register_user','login_user','get_session','logout_user','change_password',
  'request_password_reset','reset_password_with_token','revoke_other_sessions',
  'list_games','list_game_catalog','start_game','finish_game','my_scores','my_game_statistics',
  'admin_list_users_page','admin_list_scores_page','admin_list_sessions_page','admin_list_audit_page',
  'admin_list_games','admin_set_user_role','admin_set_game_active'
)
order by p.proname;

-- Direct table grants for application transport roles must remain absent.
select table_schema, table_name, privilege_type
from information_schema.role_table_grants
where grantee in ('anon','authenticated')
  and table_schema='public'
  and table_name in ('app_users','games','sessions','game_scores','game_sessions','password_reset_tokens','auth_rate_limits','game_statistics','admin_audit_log');
