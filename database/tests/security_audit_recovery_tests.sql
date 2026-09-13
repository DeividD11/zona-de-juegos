-- Pruebas de seguridad para staging.
select proname, pg_get_function_identity_arguments(p.oid) as args, count(*)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and proname in ('admin_list_games','admin_set_user_role','admin_set_game_active','request_password_reset')
group by proname, pg_get_function_identity_arguments(p.oid)
having count(*) > 1;

select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='admin_audit_log'
order by ordinal_position;

select proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and proname in ('_send_password_reset_email','admin_list_users_cursor','admin_list_scores_cursor','admin_list_sessions_cursor','admin_list_audit_cursor')
order by proname;
