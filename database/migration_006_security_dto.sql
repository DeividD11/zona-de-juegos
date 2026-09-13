-- Migración 006: endurecimiento de RPC, DTOs mínimos y permisos.
-- Ejecutar DESPUÉS de schema.sql y migraciones 002-005.

-- 0) Elimina una RPC administrativa legacy que ya no tiene consumidor.
drop function if exists public.admin_list_users(text);

-- 1) Los endpoints sensibles no son funciones públicas de escritura.
--    El navegador usa un token de sesión propio; por ello las RPC de admin
--    deben ser invocables con anon/authenticated, pero SIEMPRE pasan por
--    _require_admin(), que valida el token y el rol dentro de PostgreSQL.

create or replace function public.list_games(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._require_session(p_session_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.id,
      'slug', g.slug,
      'name', g.name,
      'description', g.description,
      'icon', g.icon,
      'score_ceiling', g.score_ceiling,
      'current_version', g.current_version
    ) order by g.name)
    from public.games g
    where g.is_active = true
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_session(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row record;
  v_hash bytea;
begin
  if nullif(trim(p_session_token), '') is null then return null; end if;
  v_hash := extensions.digest(convert_to(p_session_token, 'utf8'), 'sha256');

  select u.id, u.display_name, u.email, u.role, u.is_active, u.created_at,
         s.expires_at
  into v_row
  from public.sessions s
  join public.app_users u on u.id = s.user_id
  where s.session_token_hash = v_hash
    and s.revoked_at is null
    and s.expires_at > now()
    and s.last_seen_at > now() - interval '24 hours'
    and u.is_active = true;

  if not found then
    update public.sessions set revoked_at = now()
    where session_token_hash = v_hash and revoked_at is null;
    return null;
  end if;

  update public.sessions set last_seen_at = now()
  where session_token_hash = v_hash and revoked_at is null;

  return jsonb_build_object(
    'id', v_row.id,
    'name', v_row.display_name,
    'email', v_row.email,
    'role', v_row.role
  );
end;
$$;

create or replace function public.admin_list_games(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._require_admin(p_session_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.id,
      'slug', g.slug,
      'name', g.name,
      'description', g.description,
      'icon', g.icon,
      'score_ceiling', g.score_ceiling,
      'current_version', g.current_version,
      'is_active', g.is_active
    ) order by g.name)
    from public.games g
  ), '[]'::jsonb);
end;
$$;

-- 2) Solo los endpoints estrictamente públicos se ejecutan sin sesión.
--    Las RPC autenticadas por token propio se exponen a anon porque
--    Supabase Auth no forma parte de esta arquitectura.
revoke all on function public.admin_list_games(text) from public, anon, authenticated;
revoke all on function public.admin_list_users_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_scores_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_sessions_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_audit_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_set_user_role(text, uuid, text) from public, anon, authenticated;
revoke all on function public.admin_set_game_active(text, uuid, boolean) from public, anon, authenticated;

grant execute on function public.admin_list_games(text) to anon, authenticated;
grant execute on function public.admin_list_users_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_scores_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_sessions_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_audit_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_set_user_role(text, uuid, text) to anon, authenticated;
grant execute on function public.admin_set_game_active(text, uuid, boolean) to anon, authenticated;

-- 3) Bloquear acceso directo a las tablas sensibles.
revoke all on table public.app_users, public.games, public.sessions,
  public.game_scores, public.game_sessions, public.auth_rate_limits,
  public.password_reset_tokens, public.admin_audit_log
from anon, authenticated;

-- 4) DTO de perfil: los clientes nunca reciben password_hash.


-- SECURITY DEFINER: el rol de ejecución solo obtiene el punto de entrada;
-- la autorización efectiva ocurre dentro de cada RPC mediante _require_session/_require_admin.
