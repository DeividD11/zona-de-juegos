-- Seguridad: RPC administrativas expuestas al rol de API solo como punto de entrada; _require_admin valida el token.
-- Migración 004: integridad, índices, paginación administrativa, auditoría y versionado.
-- Ejecutar después de schema.sql/migraciones anteriores. Es idempotente.

alter table public.games
  add column if not exists current_version text not null default '1.0.0';
alter table public.games
  drop constraint if exists games_current_version_format;
alter table public.games
  add constraint games_current_version_format check (current_version ~ '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$');

update public.games
set current_version = '1.1.0'
where slug = 'snake' and current_version = '1.0.0';

-- Corrige datos antiguos antes de crear restricciones parciales/relacionales.
update public.game_sessions
set status = 'abandoned', finished_at = coalesce(finished_at, now())
where status = 'active' and finished_at is not null;

-- Elimina sesiones activas duplicadas antiguas, conservando la más reciente.
with duplicates as (
  select id, row_number() over (partition by user_id, game_id order by created_at desc, id desc) as rn
  from public.game_sessions
  where status = 'active'
)
update public.game_sessions gs
set status = 'abandoned', finished_at = coalesce(gs.finished_at, now())
from duplicates d
where gs.id = d.id and d.rn > 1;

alter table public.sessions
  drop constraint if exists sessions_expiration_after_creation;
alter table public.sessions
  add constraint sessions_expiration_after_creation check (expires_at > created_at);

alter table public.password_reset_tokens
  drop constraint if exists password_reset_tokens_expiration_after_creation;
alter table public.password_reset_tokens
  add constraint password_reset_tokens_expiration_after_creation check (expires_at > created_at);

alter table public.game_sessions
  drop constraint if exists game_sessions_expiration_after_start;
alter table public.game_sessions
  add constraint game_sessions_expiration_after_start check (expires_at > started_at);

alter table public.game_sessions
  drop constraint if exists game_sessions_status_consistency;
alter table public.game_sessions
  add constraint game_sessions_status_consistency check (
    (status = 'active' and finished_at is null and score is null)
    or (status = 'completed' and finished_at is not null and score is not null)
    or (status = 'abandoned' and finished_at is not null)
  );

drop index if exists idx_game_sessions_active;
create unique index if not exists uq_game_sessions_active_user_game
  on public.game_sessions(user_id, game_id)
  where status = 'active';

create index if not exists idx_game_sessions_created_at on public.game_sessions(created_at desc);
create index if not exists idx_game_sessions_expires_at on public.game_sessions(expires_at);
create index if not exists idx_game_scores_created_at on public.game_scores(created_at desc);

create table if not exists public.admin_audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  admin_user_id uuid references public.app_users(id) on delete set null,
  action text not null check (action in ('SET_USER_ROLE', 'SET_GAME_ACTIVE')),
  target_type text not null check (target_type in ('USER', 'GAME')),
  target_id uuid,
  occurred_at timestamptz not null default now(),
  result text not null check (result in ('success', 'error')),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_admin_audit_occurred_at on public.admin_audit_log(occurred_at desc);
create index if not exists idx_admin_audit_admin_time on public.admin_audit_log(admin_user_id, occurred_at desc);
create index if not exists idx_admin_audit_target_time on public.admin_audit_log(target_type, target_id, occurred_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;

create or replace function public.start_game(
  p_session_token text,
  p_game_slug text,
  p_game_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
  v_game record;
  v_session public.game_sessions;
  v_recent_count integer;
begin
  -- 1. Validar entrada
  if nullif(trim(p_game_slug), '') is null then
    raise exception using errcode = '22023', message = 'Juego no válido.';
  end if;

  -- 2. Validar sesión
  select user_id into v_user_id from public._require_session(p_session_token) limit 1;

  -- 3. Validar juego y autorización de acceso
  select id, slug, score_ceiling, current_version into v_game
  from public.games
  where slug = lower(trim(p_game_slug)) and is_active = true;
  if v_game.id is null then
    raise exception using errcode = '22023', message = 'El juego no está disponible.';
  end if;

  if nullif(trim(p_game_version), '') is not null and trim(p_game_version) <> v_game.current_version then
    raise exception using errcode = '22023', message = 'La versión del juego ya no está disponible. Actualiza la página.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-game-start:' || v_user_id::text || ':' || v_game.id::text, 0));

  update public.game_sessions
  set status = 'abandoned', finished_at = now()
  where user_id = v_user_id
    and game_id = v_game.id
    and status = 'active'
    and expires_at <= now();

  select count(*) into v_recent_count
  from public.game_sessions
  where user_id = v_user_id
    and game_id = v_game.id
    and created_at > now() - interval '1 minute';

  if v_recent_count >= 20 then
    raise exception using errcode = 'P0001', message = 'Has iniciado demasiadas partidas. Espera un momento e inténtalo de nuevo.';
  end if;

  update public.game_sessions
  set status = 'abandoned', finished_at = now()
  where user_id = v_user_id
    and game_id = v_game.id
    and status = 'active';

  insert into public.game_sessions(user_id, game_id, expires_at, game_version, metadata)
  values (
    v_user_id,
    v_game.id,
    now() + interval '15 minutes',
    v_game.current_version,
    jsonb_build_object('game_version', v_game.current_version)
  )
  returning * into v_session;

  return jsonb_build_object(
    'game_session_id', v_session.id,
    'game_slug', v_game.slug,
    'started_at', v_session.started_at,
    'expires_at', v_session.expires_at,
    'game_version', v_session.game_version
  );
end;
$$;

-- Mejoras 31-35: integridad, paginación, auditoría y versionado.
-- ================================================================
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

create or replace function public.admin_list_users_page(
  p_session_token text,
  p_page integer default 1,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_limit integer := least(100, greatest(1, coalesce(p_limit, 20)));
  v_total integer;
begin
  perform public._require_admin(p_session_token);
  select count(*) into v_total from public.app_users;
  return jsonb_build_object(
    'page', v_page,
    'limit', v_limit,
    'total', v_total,
    'page_count', greatest(1, ceil(v_total::numeric / v_limit)::integer),
    'data', coalesce((
      select jsonb_agg(row_to_json(x) order by x.created_at desc)
      from (
        select u.id, u.display_name, u.email, u.role, u.is_active, u.created_at
        from public.app_users u
        order by u.created_at desc
        offset (v_page - 1) * v_limit
        limit v_limit
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_list_scores_page(
  p_session_token text,
  p_page integer default 1,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_limit integer := least(100, greatest(1, coalesce(p_limit, 20)));
  v_total integer;
begin
  perform public._require_admin(p_session_token);
  select count(*) into v_total from public.game_scores;
  return jsonb_build_object(
    'page', v_page,
    'limit', v_limit,
    'total', v_total,
    'page_count', greatest(1, ceil(v_total::numeric / v_limit)::integer),
    'data', coalesce((
      select jsonb_agg(row_to_json(x) order by x.created_at desc)
      from (
        select gs.id, u.display_name, u.email, g.name as game_name, g.slug,
               gs.score, gs.created_at
        from public.game_scores gs
        join public.app_users u on u.id = gs.user_id
        join public.games g on g.id = gs.game_id
        order by gs.created_at desc
        offset (v_page - 1) * v_limit
        limit v_limit
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_list_sessions_page(
  p_session_token text,
  p_page integer default 1,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_limit integer := least(100, greatest(1, coalesce(p_limit, 20)));
  v_total integer;
begin
  perform public._require_admin(p_session_token);
  select count(*) into v_total from public.sessions;
  return jsonb_build_object(
    'page', v_page,
    'limit', v_limit,
    'total', v_total,
    'page_count', greatest(1, ceil(v_total::numeric / v_limit)::integer),
    'data', coalesce((
      select jsonb_agg(row_to_json(x) order by x.created_at desc)
      from (
        select s.id, u.display_name, u.email, s.created_at,
               s.expires_at, s.revoked_at, s.last_seen_at
        from public.sessions s
        join public.app_users u on u.id = s.user_id
        order by s.created_at desc
        offset (v_page - 1) * v_limit
        limit v_limit
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_list_audit_page(
  p_session_token text,
  p_page integer default 1,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_limit integer := least(100, greatest(1, coalesce(p_limit, 20)));
  v_total integer;
begin
  perform public._require_admin(p_session_token);
  select count(*) into v_total from public.admin_audit_log;
  return jsonb_build_object(
    'page', v_page,
    'limit', v_limit,
    'total', v_total,
    'page_count', greatest(1, ceil(v_total::numeric / v_limit)::integer),
    'data', coalesce((
      select jsonb_agg(row_to_json(x) order by x.occurred_at desc)
      from (
        select a.id, au.display_name as admin_name, a.action, a.target_type,
               a.target_id, a.occurred_at, a.result, a.metadata
        from public.admin_audit_log a
        left join public.app_users au on au.id = a.admin_user_id
        order by a.occurred_at desc
        offset (v_page - 1) * v_limit
        limit v_limit
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

-- Versionado: la versión publicada vive en games.current_version y se copia
-- a cada game_session para conservar trazabilidad histórica.
create or replace function public.admin_set_user_role(
  p_session_token text,
  p_user_id uuid,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor record;
  v_current_role text;
  v_admin_count integer;
begin
  if p_user_id is null or p_role is null or p_role not in ('admin', 'user') then
    raise exception using errcode = '22023', message = 'Datos de rol no válidos.';
  end if;
  select * into v_actor from public._require_admin(p_session_token) limit 1;
  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-admin-role-change', 0));
  select role into v_current_role from public.app_users where id = p_user_id for update;
  if v_current_role is null then
    raise exception using errcode = '22023', message = 'Usuario no encontrado.';
  end if;
  if p_user_id = v_actor.user_id and p_role <> 'admin' then
    raise exception using errcode = '42501', message = 'No puedes quitarte tu propio rol de administrador.';
  end if;
  if v_current_role = 'admin' and p_role = 'user' then
    select count(*) into v_admin_count from public.app_users where role = 'admin' and is_active = true;
    if v_admin_count <= 1 then
      raise exception using errcode = '42501', message = 'Debe existir al menos un administrador activo.';
    end if;
  end if;
  update public.app_users set role = p_role where id = p_user_id;
  insert into public.admin_audit_log(admin_user_id, action, target_type, target_id, result, metadata)
  values (v_actor.user_id, 'SET_USER_ROLE', 'USER', p_user_id, 'success',
          jsonb_build_object('from_role', v_current_role, 'to_role', p_role));
  return jsonb_build_object('success', true, 'user_id', p_user_id, 'role', p_role);
end;
$$;

create or replace function public.admin_set_game_active(
  p_session_token text,
  p_game_id uuid,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor record;
  v_previous boolean;
begin
  if p_game_id is null or p_is_active is null then
    raise exception using errcode = '22023', message = 'Datos de juego no válidos.';
  end if;
  select * into v_actor from public._require_admin(p_session_token) limit 1;
  select is_active into v_previous from public.games where id = p_game_id for update;
  if v_previous is null then
    raise exception using errcode = '22023', message = 'Juego no encontrado.';
  end if;
  update public.games set is_active = p_is_active where id = p_game_id;
  insert into public.admin_audit_log(admin_user_id, action, target_type, target_id, result, metadata)
  values (v_actor.user_id, 'SET_GAME_ACTIVE', 'GAME', p_game_id, 'success',
          jsonb_build_object('from_active', v_previous, 'to_active', p_is_active));
  return jsonb_build_object('success', true, 'game_id', p_game_id, 'is_active', p_is_active);
end;
$$;

revoke all on function public.admin_list_users_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_scores_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_sessions_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_audit_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_games(text) from public, anon, authenticated;
revoke all on function public.admin_set_user_role(text, uuid, text) from public, anon, authenticated;
revoke all on function public.admin_set_game_active(text, uuid, boolean) from public, anon, authenticated;

grant execute on function public.admin_list_users_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_scores_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_sessions_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_audit_page(text, integer, integer) to anon, authenticated;
grant execute on function public.admin_list_games(text) to anon, authenticated;
grant execute on function public.admin_set_user_role(text, uuid, text) to anon, authenticated;
grant execute on function public.admin_set_game_active(text, uuid, boolean) to anon, authenticated;
