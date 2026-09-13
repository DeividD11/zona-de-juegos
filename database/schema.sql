-- Zona de Juegos - Schema
-- Ejecutar en el SQL Editor de Supabase.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault with schema vault;
create extension if not exists pg_net;

create table if not exists public.app_users (
  id uuid primary key default extensions.gen_random_uuid(),
  display_name text not null check (char_length(trim(display_name)) between 2 and 80),
  email text not null unique check (email = lower(email)),
  password_hash text not null,
  role text not null default 'user' check (role in ('admin', 'user')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.games (
  id uuid primary key default extensions.gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  name text not null,
  description text not null default '',
  icon text not null default '🎮',
  score_ceiling integer check (score_ceiling is null or score_ceiling >= 0),
  current_version text not null default '1.0.0' check (current_version ~ '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$'),
  release_status text not null default 'available' check (release_status in ('available','upcoming')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  session_token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_seen_at timestamptz not null default now()
);

alter table public.games
  add column if not exists score_ceiling integer;
alter table public.games
  add column if not exists current_version text not null default '1.0.0';
alter table public.games
  drop constraint if exists games_current_version_format;
alter table public.games
  add constraint games_current_version_format check (current_version ~ '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$');

-- SNAKE: 20x20 celdas, 3 celdas iniciales, 10 puntos por comida.
-- El máximo defensivo se deriva de la propia lógica: (400 - 3) * 10 = 3970.
update public.games
set score_ceiling = ((20 * 20) - 3) * 10,
    current_version = '1.1.0'
where slug = 'snake' and (score_ceiling is null or score_ceiling > ((20 * 20) - 3) * 10 or current_version = '1.0.0');

create table if not exists public.game_scores (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  game_id uuid not null references public.games(id) on delete cascade,
  score integer not null check (score >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_app_users_role on public.app_users(role);
create index if not exists idx_sessions_user on public.sessions(user_id);
create index if not exists idx_sessions_expiration on public.sessions(expires_at);

create table if not exists public.password_reset_tokens (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_password_reset_tokens_user on public.password_reset_tokens(user_id, created_at desc);
create index if not exists idx_password_reset_tokens_expiration on public.password_reset_tokens(expires_at);
create index if not exists idx_game_scores_user_game on public.game_scores(user_id, game_id);
create index if not exists idx_game_scores_game_score on public.game_scores(game_id, score desc);
create table if not exists public.game_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  game_id uuid not null references public.games(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'completed', 'abandoned')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  expires_at timestamptz not null,
  score integer check (score is null or score >= 0),
  game_version text not null default '1.0.0',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.game_sessions
  add column if not exists game_version text not null default '1.0.0';

alter table public.game_sessions
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.game_sessions
  drop constraint if exists game_sessions_metadata_size;
alter table public.game_sessions
  add constraint game_sessions_metadata_size
  check (jsonb_typeof(metadata) = 'object' and octet_length(convert_to(metadata::text, 'utf8')) <= 4096);

create index if not exists idx_game_sessions_user_game on public.game_sessions(user_id, game_id, created_at desc);
create index if not exists idx_game_sessions_active on public.game_sessions(user_id, game_id, status);
create index if not exists idx_game_sessions_user_status_time on public.game_sessions(user_id, status, finished_at desc);


-- Integridad defensiva adicional: los estados de una partida no pueden quedar
-- en combinaciones imposibles y las fechas deben conservar orden temporal.
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


-- Una sola partida activa por usuario y juego evita estados concurrentes
-- innecesarios. El controlador de inicio sigue cerrando partidas anteriores.
drop index if exists idx_game_sessions_active;
create unique index if not exists uq_game_sessions_active_user_game
  on public.game_sessions(user_id, game_id)
  where status = 'active';

-- Índices administrativos y de limpieza, alineados con las consultas reales.
create index if not exists idx_game_sessions_created_at
  on public.game_sessions(created_at desc);
create index if not exists idx_game_sessions_expires_at
  on public.game_sessions(expires_at);
create index if not exists idx_game_scores_created_at
  on public.game_scores(created_at desc);

create table if not exists public.admin_audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  admin_user_id uuid references public.app_users(id) on delete set null,
  action text not null check (action in ('SET_USER_ROLE', 'SET_GAME_ACTIVE')),
  target_type text not null check (target_type in ('USER', 'GAME')),
  target_id uuid not null,
  occurred_at timestamptz not null default now(),
  result text not null check (result in ('success', 'error')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object' and octet_length(convert_to(metadata::text, 'utf8')) <= 4096)
);

create index if not exists idx_admin_audit_occurred_at
  on public.admin_audit_log(occurred_at desc);
create index if not exists idx_admin_audit_admin_time
  on public.admin_audit_log(admin_user_id, occurred_at desc);
create index if not exists idx_admin_audit_target_time
  on public.admin_audit_log(target_type, target_id, occurred_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;

create table if not exists public.auth_rate_limits (
  scope text not null,
  identifier text not null,
  attempts integer not null default 0 check (attempts >= 0),
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (scope, identifier)
);

alter table public.game_sessions enable row level security;
alter table public.auth_rate_limits enable row level security;
revoke all on public.game_sessions from public, anon, authenticated;
revoke all on public.auth_rate_limits from public, anon, authenticated;


create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_app_users_updated_at on public.app_users;
create trigger trg_app_users_updated_at
before update on public.app_users
for each row execute function public.touch_updated_at();

drop trigger if exists trg_games_updated_at on public.games;
create trigger trg_games_updated_at
before update on public.games
for each row execute function public.touch_updated_at();

-- Internal helper. It is intentionally not granted to anon/authenticated.
create or replace function public._session_user(p_session_token text)
returns table(user_id uuid, user_role text)
language sql
security definer
set search_path = public, extensions
as $$
  select u.id, u.role
  from public.sessions s
  join public.app_users u on u.id = s.user_id
  where nullif(trim(p_session_token), '') is not null
    and s.session_token_hash = extensions.digest(convert_to(p_session_token, 'utf8'), 'sha256')
    and s.revoked_at is null
    and s.expires_at > now()
    and s.last_seen_at > now() - interval '24 hours'
    and u.is_active = true;
$$;

revoke all on function public._session_user(text) from public, anon, authenticated;

-- Autorización centralizada en PostgreSQL. Las RPC públicas nunca confían en el frontend.
create or replace function public._require_session(p_session_token text)
returns table(user_id uuid, user_role text)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if nullif(trim(p_session_token), '') is null then
    raise exception using errcode = '28000', message = 'Sesión no válida o expirada.';
  end if;

  return query
  select s.user_id, s.user_role
  from public._session_user(p_session_token) s;

  if not found then
    raise exception using errcode = '28000', message = 'Sesión no válida o expirada.';
  end if;
end;
$$;

revoke all on function public._require_session(text) from public, anon, authenticated;

create or replace function public._require_admin(p_session_token text)
returns table(user_id uuid, user_role text)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return query
  select s.user_id, s.user_role
  from public._require_session(p_session_token) s
  where s.user_role = 'admin';

  if not found then
    raise exception using errcode = '42501', message = 'No tienes permisos de administrador.';
  end if;
end;
$$;

revoke all on function public._require_admin(text) from public, anon, authenticated;

create or replace function public._request_identity(p_fallback text default 'unknown')
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_headers jsonb;
  v_ip text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    v_headers := null;
  end;

  v_ip := coalesce(
    nullif(trim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(trim(v_headers ->> 'x-real-ip'), ''),
    nullif(trim(split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1)), '')
  );

  return coalesce(v_ip, nullif(trim(p_fallback), ''), 'unknown');
end;
$$;

revoke all on function public._request_identity(text) from public, anon, authenticated;

create or replace function public._rate_limit_check(
  p_scope text,
  p_identifier text,
  p_max_attempts integer,
  p_window interval
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.auth_rate_limits;
begin
  insert into public.auth_rate_limits(scope, identifier)
  values (p_scope, p_identifier)
  on conflict (scope, identifier) do nothing;

  select * into v_row
  from public.auth_rate_limits
  where scope = p_scope and identifier = p_identifier
  for update;

  if v_row.window_started_at + p_window <= now() then
    update public.auth_rate_limits
    set attempts = 0, window_started_at = now(), blocked_until = null, updated_at = now()
    where scope = p_scope and identifier = p_identifier;
    return;
  end if;

  if v_row.blocked_until is not null and v_row.blocked_until > now() then
    raise exception using errcode = 'P0001',
      message = format('Demasiados intentos. Inténtalo de nuevo en %s segundos.',
        greatest(1, ceil(extract(epoch from (v_row.blocked_until - now())))::integer));
  end if;

  if v_row.attempts >= p_max_attempts then
    update public.auth_rate_limits
    set blocked_until = now() + interval '30 seconds', updated_at = now()
    where scope = p_scope and identifier = p_identifier;
    raise exception using errcode = 'P0001', message = 'Demasiados intentos. Espera unos segundos e inténtalo de nuevo.';
  end if;
end;
$$;

revoke all on function public._rate_limit_check(text, text, integer, interval) from public, anon, authenticated;

create or replace function public._rate_limit_record(
  p_scope text,
  p_identifier text,
  p_window interval,
  p_block interval
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_attempts integer;
  v_started timestamptz;
begin
  insert into public.auth_rate_limits(scope, identifier, attempts, window_started_at, updated_at)
  values (p_scope, p_identifier, 1, now(), now())
  on conflict (scope, identifier) do update
    set attempts = case
      when public.auth_rate_limits.window_started_at + p_window <= now() then 1
      else public.auth_rate_limits.attempts + 1
    end,
    window_started_at = case
      when public.auth_rate_limits.window_started_at + p_window <= now() then now()
      else public.auth_rate_limits.window_started_at
    end,
    updated_at = now();

  select attempts, window_started_at into v_attempts, v_started
  from public.auth_rate_limits
  where scope = p_scope and identifier = p_identifier;

  if v_attempts >= 10 then
    update public.auth_rate_limits
    set blocked_until = greatest(coalesce(blocked_until, now()), now() + interval '10 minutes'), updated_at = now()
    where scope = p_scope and identifier = p_identifier;
  elsif v_attempts >= 5 then
    update public.auth_rate_limits
    set blocked_until = greatest(coalesce(blocked_until, now()), now() + p_block), updated_at = now()
    where scope = p_scope and identifier = p_identifier;
  end if;
end;
$$;

revoke all on function public._rate_limit_record(text, text, interval, interval) from public, anon, authenticated;

create or replace function public._rate_limit_reset(p_scope text, p_identifier text)
returns void
language sql
security definer
set search_path = public, extensions
as $$
  update public.auth_rate_limits
  set attempts = 0, window_started_at = now(), blocked_until = null, updated_at = now()
  where scope = p_scope and identifier = p_identifier;
$$;

revoke all on function public._rate_limit_reset(text, text) from public, anon, authenticated;

create or replace function public._rate_limit_consume(
  p_scope text, p_identifier text, p_max_attempts integer, p_window interval, p_block interval default interval '30 seconds'
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare v_row public.auth_rate_limits; v_attempts integer;
begin
  if nullif(trim(p_scope), '') is null or nullif(trim(p_identifier), '') is null or p_max_attempts <= 0 or p_window <= interval '0 seconds' then
    raise exception using errcode='22023', message='Parámetros de protección antiabuso no válidos.';
  end if;
  insert into public.auth_rate_limits(scope,identifier) values(p_scope,p_identifier) on conflict (scope,identifier) do nothing;
  select * into v_row from public.auth_rate_limits where scope=p_scope and identifier=p_identifier for update;
  if v_row.window_started_at + p_window <= now() then
    update public.auth_rate_limits set attempts=0,window_started_at=now(),blocked_until=null,updated_at=now() where scope=p_scope and identifier=p_identifier;
    v_row.attempts:=0; v_row.blocked_until:=null;
  end if;
  if v_row.blocked_until is not null and v_row.blocked_until > now() then
    raise exception using errcode='P0001', message='Demasiadas solicitudes. Espera unos segundos e inténtalo de nuevo.';
  end if;
  v_attempts:=v_row.attempts+1;
  if v_attempts > p_max_attempts then
    update public.auth_rate_limits set attempts=v_attempts,blocked_until=now()+p_block,updated_at=now() where scope=p_scope and identifier=p_identifier;
    raise exception using errcode='P0001', message='Demasiadas solicitudes. Espera unos segundos e inténtalo de nuevo.';
  end if;
  update public.auth_rate_limits set attempts=v_attempts,updated_at=now() where scope=p_scope and identifier=p_identifier;
end; $$;
revoke all on function public._rate_limit_consume(text,text,integer,interval,interval) from public,anon,authenticated;

create or replace function public._consume_operation_limits(p_operation text,p_user_id uuid default null,p_email text default null)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_ip text:=public._request_identity('no-ip'); v_subject text:=coalesce(p_user_id::text,lower(trim(p_email)),'anonymous');
begin
  perform public._rate_limit_consume(p_operation||':subject',v_subject,60,interval '1 minute',interval '30 seconds');
  perform public._rate_limit_consume(p_operation||':ip',v_ip,120,interval '1 minute',interval '30 seconds');
  perform public._rate_limit_consume(p_operation||':global','all',5000,interval '1 minute',interval '30 seconds');
end; $$;
revoke all on function public._consume_operation_limits(text,uuid,text) from public,anon,authenticated;

create or replace function public._consume_login_limits(p_email text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_email text:=lower(trim(coalesce(p_email,''))); v_ip text:=public._request_identity('no-ip');
begin
  perform public._rate_limit_consume('login:account',v_email,5,interval '15 minutes',interval '15 minutes');
  perform public._rate_limit_consume('login:ip',v_ip,30,interval '15 minutes',interval '10 minutes');
  perform public._rate_limit_consume('login:global','all',1000,interval '1 minute',interval '1 minute');
end; $$;
revoke all on function public._consume_login_limits(text) from public,anon,authenticated;


-- Política de sesiones:
-- máximo absoluto: 7 días; inactividad máxima: 24 horas; máximo 5 sesiones activas por usuario.
create or replace function public.cleanup_sessions()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deleted integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-session-cleanup', 0));

  delete from public.sessions
  where expires_at <= now()
     or revoked_at <= now() - interval '1 day'
     or last_seen_at <= now() - interval '2 days';

  delete from public.password_reset_tokens
  where expires_at <= now() or used_at <= now() - interval '1 day';

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_sessions() from public, anon, authenticated;

create or replace function public.revoke_other_sessions(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor record;
  v_revoked integer;
begin
  select * into v_actor from public._require_session(p_session_token) limit 1;

  update public.sessions
  set revoked_at = now()
  where user_id = v_actor.user_id
    and revoked_at is null
    and session_token_hash <> extensions.digest(convert_to(p_session_token, 'utf8'), 'sha256');

  get diagnostics v_revoked = row_count;

  return jsonb_build_object('success', true, 'revoked_sessions', v_revoked);
end;
$$;

revoke all on function public.revoke_other_sessions(text) from public, anon, authenticated;

create or replace function public.register_user(
  p_display_name text,
  p_email text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user public.app_users;
  v_token text;
  v_expires timestamptz;
  v_email text;
begin
  -- 1. Validar entrada
  v_email := lower(trim(coalesce(p_email, '')));
  if trim(coalesce(p_display_name, '')) = '' or char_length(trim(p_display_name)) < 2 then
    raise exception using errcode = '22023', message = 'El nombre debe tener al menos 2 caracteres.';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception using errcode = '22023', message = 'El correo electrónico no es válido.';
  end if;
  if char_length(coalesce(p_password, '')) < 8 then
    raise exception using errcode = '22023', message = 'La contraseña debe tener al menos 8 caracteres.';
  end if;
  if char_length(coalesce(p_password, '')) > 128 then
    raise exception using errcode = '22023', message = 'La contraseña no puede superar 128 caracteres.';
  end if;

  -- 2. Límite por cuenta/correo, IP disponible y operación global.
  perform public._consume_operation_limits('register_user', null, v_email);

  insert into public.app_users(display_name, email, password_hash, role)
  values (
    trim(p_display_name),
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    'user'
  )
  returning * into v_user;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + interval '7 days';

  insert into public.sessions(user_id, session_token_hash, expires_at)
  values (v_user.id, extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), v_expires);

  -- Mantenimiento oportunista; el job periódico se define en maintenance.sql.
  perform public.cleanup_sessions();

  return jsonb_build_object(
    'session_token', v_token,
    'expires_at', v_expires,
    'user', jsonb_build_object(
      'id', v_user.id,
      'display_name', v_user.display_name,
      'email', v_user.email,
      'role', v_user.role,
      'is_active', v_user.is_active,
      'created_at', v_user.created_at
    )
  );
exception
  when unique_violation then
    raise exception using errcode = '23505', message = 'Ya existe un usuario con ese correo.';
end;
$$;

create or replace function public.login_user(
  p_email text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user public.app_users;
  v_token text;
  v_expires timestamptz;
  v_email text;
  v_active_sessions integer;
begin
  -- 1. Validar entrada
  v_email := lower(trim(coalesce(p_email, '')));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or nullif(p_password, '') is null then
    raise exception using errcode = '28000', message = 'Correo o contraseña incorrectos.';
  end if;

  -- 2. Protección antiabuso: cuenta + IP disponible + operación global.
  perform public._consume_login_limits(v_email);

  -- 3. Buscar y validar credenciales
  select * into v_user
  from public.app_users
  where email = v_email
    and is_active = true;

  if not found or not (v_user.password_hash = extensions.crypt(p_password, v_user.password_hash)) then
    raise exception using errcode = '28000', message = 'Correo o contraseña incorrectos.';
  end if;

  -- 4. Serializar sesiones del usuario y mantener un máximo de 5.
  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-user-sessions:' || v_user.id::text, 0));
  delete from public.sessions
  where user_id = v_user.id
    and (expires_at <= now()
      or revoked_at is not null
      or last_seen_at <= now() - interval '24 hours');

  select count(*) into v_active_sessions
  from public.sessions
  where user_id = v_user.id
    and revoked_at is null
    and expires_at > now()
    and last_seen_at > now() - interval '24 hours';

  if v_active_sessions >= 5 then
    update public.sessions
    set revoked_at = now()
    where id = (
      select id from public.sessions
      where user_id = v_user.id
        and revoked_at is null
        and expires_at > now()
        and last_seen_at > now() - interval '24 hours'
      order by last_seen_at asc, created_at asc
      limit 1
    );
  end if;

  perform public.cleanup_sessions();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + interval '7 days';

  insert into public.sessions(user_id, session_token_hash, expires_at)
  values (v_user.id, extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), v_expires);

  return jsonb_build_object(
    'session_token', v_token,
    'expires_at', v_expires,
    'user', jsonb_build_object(
      'id', v_user.id,
      'display_name', v_user.display_name,
      'email', v_user.email,
      'role', v_user.role,
      'is_active', v_user.is_active,
      'created_at', v_user.created_at
    )
  );
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
  if nullif(trim(p_session_token), '') is null then
    return null;
  end if;

  v_hash := extensions.digest(convert_to(p_session_token, 'utf8'), 'sha256');

  select u.id, u.display_name, u.email, u.role, u.is_active, u.created_at,
         s.expires_at, s.last_seen_at
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

  update public.sessions
  set last_seen_at = now()
  where session_token_hash = v_hash
    and revoked_at is null;

  return jsonb_build_object(
    'id', v_row.id,
    'name', v_row.display_name,
    'email', v_row.email,
    'role', v_row.role
  );
end;
$$;

create or replace function public.change_password(
  p_session_token text,
  p_current_password text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor record;
  v_user public.app_users;
  v_hash bytea;
  v_current_ok boolean;
  v_revoked integer;
begin
  if nullif(p_current_password, '') is null or nullif(p_new_password, '') is null then
    raise exception using errcode = '22023', message = 'Debes completar la contraseña actual y la nueva contraseña.';
  end if;
  if char_length(p_new_password) < 8 then
    raise exception using errcode = '22023', message = 'La nueva contraseña debe tener al menos 8 caracteres.';
  end if;
  if char_length(p_new_password) > 128 then
    raise exception using errcode = '22023', message = 'La nueva contraseña no puede superar 128 caracteres.';
  end if;

  select * into v_actor from public._require_session(p_session_token) limit 1;
  select * into v_user from public.app_users where id = v_actor.user_id and is_active = true for update;
  if not found then
    raise exception using errcode = '28000', message = 'Sesión expirada.';
  end if;

  v_current_ok := v_user.password_hash = extensions.crypt(p_current_password, v_user.password_hash);
  if not v_current_ok then
    raise exception using errcode = '28000', message = 'La contraseña actual no es correcta.';
  end if;
  if p_current_password = p_new_password then
    raise exception using errcode = '22023', message = 'La nueva contraseña debe ser diferente a la actual.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-password-change:' || v_user.id::text, 0));
  update public.app_users
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12))
  where id = v_user.id;

  v_hash := extensions.digest(convert_to(p_session_token, 'utf8'), 'sha256');
  update public.sessions
  set revoked_at = now()
  where user_id = v_user.id
    and revoked_at is null
    and session_token_hash <> v_hash;
  get diagnostics v_revoked = row_count;

  delete from public.password_reset_tokens where user_id = v_user.id and used_at is null;

  return jsonb_build_object('success', true, 'revoked_sessions', v_revoked);
end;
$$;

create or replace function public._send_password_reset_email(
  p_recipient text,
  p_token text
)
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_api_key text;
  v_from text;
  v_app_url text;
  v_request_id bigint;
begin
  select decrypted_secret into v_api_key
  from vault.decrypted_secrets
  where name = 'password_reset_resend_api_key'
  limit 1;

  select decrypted_secret into v_from
  from vault.decrypted_secrets
  where name = 'password_reset_from_email'
  limit 1;

  select decrypted_secret into v_app_url
  from vault.decrypted_secrets
  where name = 'password_reset_app_url'
  limit 1;

  if nullif(trim(v_api_key),'') is null
     or nullif(trim(v_from),'') is null
     or nullif(trim(v_app_url),'') is null then
    raise exception using errcode='55000', message='El servicio de recuperación de contraseña no está configurado.';
  end if;

  v_request_id := net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_api_key
    ),
    body := jsonb_build_object(
      'from', v_from,
      'to', jsonb_build_array(p_recipient),
      'subject', 'Recuperación de contraseña',
      'text', 'Solicitaste restablecer tu contraseña. Abre este enlace para continuar: ' || rtrim(v_app_url, '/') || '?token=' || p_token || '. El enlace vence en 30 minutos.',
      'html', '<p>Solicitaste restablecer tu contraseña.</p><p><a href="' || rtrim(v_app_url, '/') || '?token=' || p_token || '">Restablecer contraseña</a></p><p>El enlace vence en 30 minutos. Si no solicitaste el cambio, puedes ignorar este mensaje.</p>'
    ),
    timeout_milliseconds := 2000
  );

  if v_request_id is null then
    raise exception using errcode='55000', message='No se pudo encolar el correo de recuperación.';
  end if;
end;
$$;

revoke all on function public._send_password_reset_email(text,text) from public, anon, authenticated;

create or replace function public.request_password_reset(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_user public.app_users;
  v_token text;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('success', true);
  end if;

  perform public._consume_operation_limits('password_reset', null, v_email);

  select * into v_user
  from public.app_users
  where email = v_email and is_active = true
  limit 1;

  if found then
    delete from public.password_reset_tokens where user_id = v_user.id and used_at is null;
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.password_reset_tokens(user_id, token_hash, expires_at)
    values (v_user.id, extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), now() + interval '30 minutes');

    -- El token se entrega únicamente al proveedor de correo; nunca se devuelve al cliente.
    perform public._send_password_reset_email(v_user.email, v_token);
  end if;

  -- Respuesta uniforme para no filtrar si el correo existe.
  return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.request_password_reset(text) from public, anon, authenticated;
grant execute on function public.request_password_reset(text) to anon;



create or replace function public.reset_password_with_token(
  p_token text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_reset public.password_reset_tokens;
  v_user public.app_users;
  v_hash bytea;
  v_revoked integer;
begin
  if nullif(trim(p_token), '') is null then
    raise exception using errcode = '28000', message = 'El enlace de recuperación no es válido.';
  end if;
  if char_length(coalesce(p_new_password, '')) < 8 then
    raise exception using errcode = '22023', message = 'La nueva contraseña debe tener al menos 8 caracteres.';
  end if;
  if char_length(coalesce(p_new_password, '')) > 128 then
    raise exception using errcode = '22023', message = 'La nueva contraseña no puede superar 128 caracteres.';
  end if;

  v_hash := extensions.digest(convert_to(trim(p_token), 'utf8'), 'sha256');
  select * into v_reset
  from public.password_reset_tokens
  where token_hash = v_hash
    and used_at is null
    and expires_at > now()
  for update;

  if not found then
    raise exception using errcode = '28000', message = 'El enlace de recuperación no es válido o ya expiró.';
  end if;

  select * into v_user from public.app_users where id = v_reset.user_id and is_active = true for update;
  if not found then
    raise exception using errcode = '28000', message = 'La cuenta no está disponible.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-password-reset:' || v_user.id::text, 0));
  update public.app_users
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12))
  where id = v_user.id;

  update public.password_reset_tokens set used_at = now() where id = v_reset.id;
  update public.sessions set revoked_at = now() where user_id = v_user.id and revoked_at is null;
  get diagnostics v_revoked = row_count;

  return jsonb_build_object('success', true, 'revoked_sessions', v_revoked);
end;
$$;

revoke all on function public.change_password(text, text, text) from public, anon, authenticated;
revoke all on function public.request_password_reset(text) from public, anon, authenticated;
revoke all on function public.reset_password_with_token(text, text) from public, anon, authenticated;

create or replace function public.logout_user(p_session_token text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if nullif(trim(p_session_token), '') is null then
    return true;
  end if;

  update public.sessions
  set revoked_at = now()
  where session_token_hash = extensions.digest(convert_to(p_session_token, 'utf8'), 'sha256')
    and revoked_at is null;

  return true;
end;
$$;

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

drop function if exists public.save_score(text, text, integer);

drop function if exists public._validate_game_metadata(jsonb);

create or replace function public._validate_game_metadata(p_metadata jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_keys text[];
begin
  if p_metadata is null then
    return;
  end if;
  if jsonb_typeof(p_metadata) <> 'object' then
    raise exception using errcode='22023', message='La metadata de la partida debe ser un objeto JSON.';
  end if;
  if octet_length(convert_to(p_metadata::text, 'utf8')) > 4096 then
    raise exception using errcode='22023', message='La metadata de la partida es demasiado grande.';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_keys
  from jsonb_object_keys(p_metadata) as key;
  if exists (
    select 1 from unnest(v_keys) key
    where key not in ('start_time','end_time','duration','score','game_version')
  ) then
    raise exception using errcode='22023', message='La metadata contiene campos no permitidos.';
  end if;
  if p_metadata ? 'duration' and jsonb_typeof(p_metadata->'duration') <> 'number' then
    raise exception using errcode='22023', message='La duración de la partida no es válida.';
  end if;
  if p_metadata ? 'score' and jsonb_typeof(p_metadata->'score') <> 'number' then
    raise exception using errcode='22023', message='La puntuación de la metadata no es válida.';
  end if;
  if p_metadata ? 'game_version' and jsonb_typeof(p_metadata->'game_version') <> 'string' then
    raise exception using errcode='22023', message='La versión del juego no es válida.';
  end if;
end;
$$;

revoke all on function public._validate_game_metadata(jsonb) from public, anon, authenticated;

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
  perform public._consume_operation_limits('start_game', v_user_id, null);

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

  if v_recent_count >= 10 then
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

drop function if exists public.finish_game(text, uuid, integer);

create or replace function public.finish_game(
  p_session_token text,
  p_game_session_id uuid,
  p_score integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
  v_game_session public.game_sessions;
  v_game public.games;
  v_best integer;
  v_elapsed numeric;
  v_max_by_time integer;
  v_recent_scores integer;
begin
  -- 1. Validar entrada
  if p_game_session_id is null or p_score is null or p_score < 0 then
    raise exception using errcode = '22023', message = 'Resultado de partida no válido.';
  end if;

  -- 2. Validar sesión
  select user_id into v_user_id from public._require_session(p_session_token) limit 1;
  perform public._consume_operation_limits('finish_game', v_user_id, null);
  perform public._validate_game_metadata(coalesce(p_metadata, '{}'::jsonb));

  -- 3. Validar propiedad de la partida
  select * into v_game_session
  from public.game_sessions
  where id = p_game_session_id and user_id = v_user_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'La partida no existe o no te pertenece.';
  end if;

  if v_game_session.status <> 'active' then
    raise exception using errcode = '22023', message = 'La partida ya fue cerrada.';
  end if;

  if v_game_session.expires_at <= now() then
    update public.game_sessions
    set status = 'abandoned', finished_at = now()
    where id = v_game_session.id;
    raise exception using errcode = '22023', message = 'La partida expiró. Inicia una nueva partida.';
  end if;

  select * into v_game from public.games where id = v_game_session.game_id;

  select count(*) into v_recent_scores
  from public.game_sessions
  where user_id = v_user_id
    and status = 'completed'
    and finished_at > now() - interval '1 minute';

  if v_recent_scores >= 10 then
    raise exception using errcode = 'P0001', message = 'Has enviado demasiados resultados. Espera un momento.';
  end if;

  if v_game.score_ceiling is not null and p_score > v_game.score_ceiling then
    raise exception using errcode = '22023', message = 'La puntuación supera el máximo permitido para este juego.';
  end if;

  v_elapsed := greatest(0, extract(epoch from (least(now(), v_game_session.expires_at) - v_game_session.started_at)));
  v_max_by_time := floor(v_elapsed / 0.11) * 10;

  if p_score > v_max_by_time then
    raise exception using errcode = '22023', message = 'La puntuación no es compatible con la duración de la partida.';
  end if;

  if v_game.slug = 'snake' and mod(p_score, 10) <> 0 then
    raise exception using errcode = '22023', message = 'La puntuación de SNAKE no es válida.';
  end if;

  if p_metadata ? 'score' and (p_metadata->>'score')::numeric <> p_score then
    raise exception using errcode = '22023', message = 'La puntuación de metadata no coincide con el resultado.';
  end if;
  if p_metadata ? 'game_version' and p_metadata->>'game_version' <> v_game_session.game_version then
    raise exception using errcode = '22023', message = 'La versión de metadata no coincide con la partida.';
  end if;
  if p_metadata ? 'duration' and abs((p_metadata->>'duration')::numeric - v_elapsed) > 2 then
    raise exception using errcode = '22023', message = 'La duración de metadata no coincide con la partida.';
  end if;

  update public.game_sessions
  set status = 'completed',
      finished_at = now(),
      score = p_score,
      metadata = coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object(
        'start_time', v_game_session.started_at,
        'end_time', now(),
        'duration', greatest(0, extract(epoch from (now() - v_game_session.started_at))),
        'score', p_score,
        'game_version', v_game_session.game_version
      )
  where id = v_game_session.id;

  insert into public.game_scores(user_id, game_id, score)
  values (v_user_id, v_game_session.game_id, p_score);

  select max(score) into v_best
  from public.game_scores
  where user_id = v_user_id and game_id = v_game_session.game_id;

  return jsonb_build_object(
    'score', p_score,
    'best_score', coalesce(v_best, p_score),
    'game_session_id', v_game_session.id,
    'start_time', v_game_session.started_at,
    'end_time', now(),
    'duration', greatest(0, extract(epoch from (now() - v_game_session.started_at))),
    'game_version', v_game_session.game_version
  );
end;
$$;

revoke all on function public.start_game(text, text, text) from public, anon, authenticated;
revoke all on function public.finish_game(text, uuid, integer, jsonb) from public, anon, authenticated;

create or replace function public.my_scores(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id from public._require_session(p_session_token) limit 1;

  return coalesce((
    select jsonb_agg(x order by x.best_score desc, x.game_name)
    from (
      select g.slug, g.name as game_name, max(gs.score) as best_score, max(gs.created_at) as last_played
      from public.game_scores gs
      join public.games g on g.id = gs.game_id
      where gs.user_id = v_user_id
      group by g.slug, g.name
    ) x
  ), '[]'::jsonb);
end;
$$;

-- RPC administrativa anterior reemplazada por operaciones de dominio separadas.
drop function if exists public.admin_get_data(text);
drop function if exists public.admin_list_users(text);

create or replace function public.admin_list_users(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._require_admin(p_session_token);

  return (
    select coalesce(jsonb_agg(to_jsonb(u) - 'password_hash' order by u.created_at desc), '[]'::jsonb)
    from public.app_users u
  );
end;
$$;



revoke all on function public.admin_list_users(text) from public, anon, authenticated;
revoke all on function public.admin_list_games(text) from public, anon, authenticated;








create or replace function public._admin_audit(
  p_actor uuid,
  p_action text,
  p_target_type text,
  p_target_id uuid,
  p_result text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_target_type not in ('USER','GAME') then
    raise exception using errcode='22023', message='Tipo de objetivo de auditoría no válido.';
  end if;
  if p_result not in ('success','error') then
    raise exception using errcode='22023', message='Resultado de auditoría no válido.';
  end if;
  if octet_length(convert_to(coalesce(p_metadata,'{}'::jsonb)::text,'utf8')) > 4096 then
    raise exception using errcode='22023', message='Metadata de auditoría demasiado grande.';
  end if;

  insert into public.admin_audit_log(admin_user_id, action, target_type, target_id, occurred_at, result, metadata)
  values (p_actor, p_action, p_target_type, p_target_id, now(), p_result, coalesce(p_metadata,'{}'::jsonb));
end;
$$;

revoke all on function public._admin_audit(uuid,text,text,uuid,text,jsonb) from public, anon, authenticated;


-- ================================================================
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
  return (
    select coalesce(jsonb_agg(to_jsonb(g) order by g.name), '[]'::jsonb)
    from public.games g
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


-- ================================================================
-- Estado consolidado del esquema (migraciones 007-009 absorbidas)
-- ================================================================

alter table public.games
  add column if not exists release_status text not null default 'available';

alter table public.games
  drop constraint if exists games_release_status_check;
alter table public.games
  add constraint games_release_status_check
  check (release_status in ('available', 'upcoming'));

update public.games set release_status = 'available'
where release_status is null;

create table if not exists public.game_statistics (
  user_id uuid not null references public.app_users(id) on delete cascade,
  game_id uuid not null references public.games(id) on delete cascade,
  games_played integer not null default 0 check (games_played >= 0),
  total_score bigint not null default 0 check (total_score >= 0),
  best_score integer not null default 0 check (best_score >= 0),
  last_played_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, game_id)
);

create index if not exists idx_game_statistics_game_best
  on public.game_statistics(game_id, best_score desc, last_played_at desc);
create index if not exists idx_game_statistics_last_played
  on public.game_statistics(last_played_at desc);

alter table public.game_statistics enable row level security;
revoke all on public.game_statistics from public, anon, authenticated;

create or replace function public.refresh_game_statistics(
  p_user_id uuid, p_game_id uuid, p_score integer, p_played_at timestamptz
) returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  insert into public.game_statistics(
    user_id, game_id, games_played, total_score, best_score, last_played_at, updated_at
  ) values (p_user_id, p_game_id, 1, p_score, p_score, p_played_at, now())
  on conflict (user_id, game_id) do update
  set games_played = public.game_statistics.games_played + 1,
      total_score = public.game_statistics.total_score + excluded.total_score,
      best_score = greatest(public.game_statistics.best_score, excluded.best_score),
      last_played_at = greatest(public.game_statistics.last_played_at, excluded.last_played_at),
      updated_at = now();
end;
$$;
revoke all on function public.refresh_game_statistics(uuid, uuid, integer, timestamptz) from public, anon, authenticated;

create or replace function public.sync_game_statistics_after_score()
returns trigger language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform public.refresh_game_statistics(new.user_id, new.game_id, new.score, new.created_at);
  return new;
end;
$$;
revoke all on function public.sync_game_statistics_after_score() from public, anon, authenticated;
drop trigger if exists trg_sync_game_statistics on public.game_scores;
create trigger trg_sync_game_statistics after insert on public.game_scores
for each row execute function public.sync_game_statistics_after_score();

create or replace function public.list_game_catalog(p_session_token text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare v_user_id uuid;
begin
  select user_id into v_user_id from public._require_session(p_session_token) limit 1;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',g.id,'slug',g.slug,'name',g.name,'description',g.description,'icon',g.icon,
    'score_ceiling',g.score_ceiling,'current_version',g.current_version,
    'release_status',case when not g.is_active then 'disabled' else g.release_status end,
    'is_active',g.is_active,'best_score',coalesce((select max(gs.score) from public.game_scores gs where gs.user_id=v_user_id and gs.game_id=g.id),0)
  ) order by case when g.is_active and g.release_status='available' then 0 when g.is_active and g.release_status='upcoming' then 1 else 2 end, g.name) from public.games g),'[]'::jsonb);
end;
$$;

create or replace function public.my_game_statistics(p_session_token text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare v_user_id uuid;
begin
  select user_id into v_user_id from public._require_session(p_session_token) limit 1;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'slug',g.slug,'game_name',g.name,'games_played',s.games_played,'total_score',s.total_score,
    'best_score',s.best_score,'last_played_at',s.last_played_at
  ) order by s.best_score desc,g.name) from public.game_statistics s join public.games g on g.id=s.game_id where s.user_id=v_user_id),'[]'::jsonb);
end;
$$;

-- Rankings: derivaciones separadas de los resultados históricos.
create or replace view public.leaderboard_global as
select s.game_id,g.slug as game_slug,g.name as game_name,s.user_id,u.display_name,s.best_score,s.games_played,s.last_played_at,
       dense_rank() over(partition by s.game_id order by s.best_score desc,s.last_played_at asc nulls last,s.user_id) as ranking_position
from public.game_statistics s join public.games g on g.id=s.game_id join public.app_users u on u.id=s.user_id
where u.is_active and g.is_active;

create or replace view public.leaderboard_weekly as
select gs.game_id,g.slug as game_slug,g.name as game_name,gs.user_id,u.display_name,max(gs.score) as best_score,count(*)::integer as games_played,max(gs.created_at) as last_played_at,
       dense_rank() over(partition by gs.game_id order by max(gs.score) desc,max(gs.created_at) asc,gs.user_id) as ranking_position
from public.game_scores gs join public.games g on g.id=gs.game_id join public.app_users u on u.id=gs.user_id
where gs.created_at >= date_trunc('week',now()) and u.is_active and g.is_active
group by gs.game_id,g.slug,g.name,gs.user_id,u.display_name;

create or replace view public.leaderboard_monthly as
select gs.game_id,g.slug as game_slug,g.name as game_name,gs.user_id,u.display_name,max(gs.score) as best_score,count(*)::integer as games_played,max(gs.created_at) as last_played_at,
       dense_rank() over(partition by gs.game_id order by max(gs.score) desc,max(gs.created_at) asc,gs.user_id) as ranking_position
from public.game_scores gs join public.games g on g.id=gs.game_id join public.app_users u on u.id=gs.user_id
where gs.created_at >= date_trunc('month',now()) and u.is_active and g.is_active
group by gs.game_id,g.slug,g.name,gs.user_id,u.display_name;
revoke all on public.leaderboard_global from public,anon,authenticated;
revoke all on public.leaderboard_weekly from public,anon,authenticated;
revoke all on public.leaderboard_monthly from public,anon,authenticated;

create or replace function public.admin_list_users_page(p_session_token text,p_page integer default 1,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_page integer:=greatest(1,coalesce(p_page,1)); v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_total integer;
begin perform public._require_admin(p_session_token); select count(*) into v_total from public.app_users; return jsonb_build_object('page',v_page,'limit',v_limit,'total',v_total,'page_count',greatest(1,ceil(v_total::numeric/v_limit)::integer),'data',coalesce((select jsonb_agg(row_to_json(x) order by x.created_at desc) from (select id,display_name,email,role,is_active,created_at from public.app_users order by created_at desc offset (v_page-1)*v_limit limit v_limit)x),'[]'::jsonb)); end; $$;

create or replace function public.admin_list_scores_page(p_session_token text,p_page integer default 1,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_page integer:=greatest(1,coalesce(p_page,1)); v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_total integer;
begin perform public._require_admin(p_session_token); select count(*) into v_total from public.game_scores; return jsonb_build_object('page',v_page,'limit',v_limit,'total',v_total,'page_count',greatest(1,ceil(v_total::numeric/v_limit)::integer),'data',coalesce((select jsonb_agg(row_to_json(x) order by x.created_at desc) from (select gs.id,u.display_name,u.email,g.name as game_name,g.slug,gs.score,gs.created_at from public.game_scores gs join public.app_users u on u.id=gs.user_id join public.games g on g.id=gs.game_id order by gs.created_at desc offset (v_page-1)*v_limit limit v_limit)x),'[]'::jsonb)); end; $$;

create or replace function public.admin_list_sessions_page(p_session_token text,p_page integer default 1,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_page integer:=greatest(1,coalesce(p_page,1)); v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_total integer;
begin perform public._require_admin(p_session_token); select count(*) into v_total from public.sessions; return jsonb_build_object('page',v_page,'limit',v_limit,'total',v_total,'page_count',greatest(1,ceil(v_total::numeric/v_limit)::integer),'data',coalesce((select jsonb_agg(row_to_json(x) order by x.created_at desc) from (select s.id,u.display_name,u.email,s.created_at,s.expires_at,s.revoked_at,s.last_seen_at from public.sessions s join public.app_users u on u.id=s.user_id order by s.created_at desc offset (v_page-1)*v_limit limit v_limit)x),'[]'::jsonb)); end; $$;

create or replace function public.admin_list_audit_page(p_session_token text,p_page integer default 1,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_page integer:=greatest(1,coalesce(p_page,1)); v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_total integer;
begin perform public._require_admin(p_session_token); select count(*) into v_total from public.admin_audit_log; return jsonb_build_object('page',v_page,'limit',v_limit,'total',v_total,'page_count',greatest(1,ceil(v_total::numeric/v_limit)::integer),'data',coalesce((select jsonb_agg(row_to_json(x) order by x.occurred_at desc) from (select a.id,au.display_name as admin_name,a.action,a.target_type,a.target_id,a.occurred_at,a.result,a.metadata from public.admin_audit_log a left join public.app_users au on au.id=a.admin_user_id order by a.occurred_at desc offset (v_page-1)*v_limit limit v_limit)x),'[]'::jsonb)); end; $$;

-- ================================================================
-- Paginación por cursor. Las RPC *_page existentes permanecen como compatibilidad.
-- Cursor = created_at + id codificados en base64url.
-- ================================================================
create or replace function public._encode_cursor(p_created_at timestamptz, p_id uuid)
returns text
language sql immutable
security definer
set search_path = public, extensions
as $$
  select replace(replace(rtrim(encode(convert_to(to_char(p_created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || p_id::text,'utf8'),'base64'),'='),'+','-'),'/', '_');
$$;
revoke all on function public._encode_cursor(timestamptz,uuid) from public, anon, authenticated;

create or replace function public._decode_cursor(p_cursor text)
returns table(created_at timestamptz, id uuid)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_raw text;
  v_parts text[];
begin
  if nullif(trim(p_cursor),'') is null then return; end if;
  v_raw := convert_from(decode(replace(replace(p_cursor,'-','+'),'_','/') || repeat('=', (4 - length(p_cursor) % 4) % 4),'base64'),'utf8');
  v_parts := string_to_array(v_raw,'|');
  if array_length(v_parts,1) <> 2 then
    raise exception using errcode='22023', message='Cursor no válido.';
  end if;
  created_at := v_parts[1]::timestamptz;
  id := v_parts[2]::uuid;
  return next;
exception
  when others then
    raise exception using errcode='22023', message='Cursor no válido.';
end;
$$;
revoke all on function public._decode_cursor(text) from public, anon, authenticated;

create or replace function public.admin_list_users_cursor(
  p_session_token text,
  p_cursor text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_limit integer := least(100,greatest(1,coalesce(p_limit,20)));
  v_cur timestamptz;
  v_id uuid;
  v_rows jsonb;
  v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then
    select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1;
  end if;

  with rows as (
    select id,display_name,email,role,is_active,created_at
    from public.app_users
    where v_cur is null or (created_at,id) < (v_cur,v_id)
    order by created_at desc,id desc
    limit v_limit + 1
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]'::jsonb),
         (select public._encode_cursor(created_at,id) from rows order by created_at asc,id asc offset 1 limit 1)
  into v_rows,v_next
  from rows r;

  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows) > v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n <= v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

create or replace function public.admin_list_scores_cursor(p_session_token text,p_cursor text default null,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_cur timestamptz; v_id uuid; v_rows jsonb; v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1; end if;
  with rows as (select gs.id,u.display_name,u.email,g.name as game_name,g.slug,gs.score,gs.created_at from public.game_scores gs join public.app_users u on u.id=gs.user_id join public.games g on g.id=gs.game_id where v_cur is null or (gs.created_at,gs.id)<(v_cur,v_id) order by gs.created_at desc,gs.id desc limit v_limit+1)
  select coalesce(jsonb_agg(row_to_json(r) order by r.created_at desc,r.id desc),'[]'::jsonb),(select public._encode_cursor(created_at,id) from rows order by created_at asc,id asc offset 1 limit 1) into v_rows,v_next from rows r;
  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows)>v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n<=v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

create or replace function public.admin_list_sessions_cursor(p_session_token text,p_cursor text default null,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_cur timestamptz; v_id uuid; v_rows jsonb; v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1; end if;
  with rows as (select s.id,u.display_name,u.email,s.created_at,s.expires_at,s.revoked_at,s.last_seen_at from public.sessions s join public.app_users u on u.id=s.user_id where v_cur is null or (s.created_at,s.id)<(v_cur,v_id) order by s.created_at desc,s.id desc limit v_limit+1)
  select coalesce(jsonb_agg(row_to_json(r) order by r.created_at desc,r.id desc),'[]'::jsonb),(select public._encode_cursor(created_at,id) from rows order by created_at asc,id asc offset 1 limit 1) into v_rows,v_next from rows r;
  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows)>v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n<=v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

create or replace function public.admin_list_audit_cursor(p_session_token text,p_cursor text default null,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_cur timestamptz; v_id uuid; v_rows jsonb; v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1; end if;
  with rows as (select a.id,au.display_name as admin_name,a.action,a.target_type,a.target_id,a.occurred_at,a.result,a.metadata from public.admin_audit_log a left join public.app_users au on au.id=a.admin_user_id where v_cur is null or (a.occurred_at,a.id)<(v_cur,v_id) order by a.occurred_at desc,a.id desc limit v_limit+1)
  select coalesce(jsonb_agg(row_to_json(r) order by r.occurred_at desc,r.id desc),'[]'::jsonb),(select public._encode_cursor(occurred_at,id) from rows order by occurred_at asc,id asc offset 1 limit 1) into v_rows,v_next from rows r;
  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows)>v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n<=v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

revoke all on function public.admin_list_users_cursor(text,text,integer) from public,anon,authenticated;
revoke all on function public.admin_list_scores_cursor(text,text,integer) from public,anon,authenticated;
revoke all on function public.admin_list_sessions_cursor(text,text,integer) from public,anon,authenticated;
revoke all on function public.admin_list_audit_cursor(text,text,integer) from public,anon,authenticated;
grant execute on function public.admin_list_users_cursor(text,text,integer) to anon;
grant execute on function public.admin_list_scores_cursor(text,text,integer) to anon;
grant execute on function public.admin_list_sessions_cursor(text,text,integer) to anon;
grant execute on function public.admin_list_audit_cursor(text,text,integer) to anon;

-- Registrar juegos de la hoja de ruta de forma idempotente.
insert into public.games(slug,name,description,icon,score_ceiling,current_version,release_status,is_active) values
('snake','SNAKE','Come, crece y sobrevive todo lo que puedas sin chocar contigo mismo.','🐍',3970,'1.1.0','available',true),
('tetris','TETRIS','Construye líneas y prepara el tablero para la próxima caída.','🧱',0,'0.1.0','upcoming',false),
('pong','PONG','El clásico duelo de paletas estará disponible próximamente.','🏓',0,'0.1.0','upcoming',false),
('memory','MEMORY','Encuentra las parejas y mejora tu memoria.','🧠',0,'0.1.0','upcoming',false),
('minesweeper','MINESWEEPER','Descubre el tablero evitando las minas.','💣',0,'0.1.0','upcoming',false)
on conflict (slug) do update set name=excluded.name,description=excluded.description,icon=excluded.icon,score_ceiling=excluded.score_ceiling,current_version=excluded.current_version,release_status=excluded.release_status,is_active=excluded.is_active;

-- Backfill de estadísticas existente.
insert into public.game_statistics(user_id,game_id,games_played,total_score,best_score,last_played_at,updated_at)
select gs.user_id,gs.game_id,count(*)::integer,coalesce(sum(gs.score),0),coalesce(max(gs.score),0),max(gs.created_at),now() from public.game_scores gs group by gs.user_id,gs.game_id
on conflict (user_id,game_id) do update set games_played=excluded.games_played,total_score=excluded.total_score,best_score=excluded.best_score,last_played_at=excluded.last_played_at,updated_at=now();

-- ================================================================
-- Configuración RLS consolidada para instalación desde cero.
-- Las RPC SECURITY DEFINER constituyen la API; las tablas no se exponen
-- directamente a los roles de transporte.
-- ================================================================
alter table public.app_users enable row level security;
alter table public.games enable row level security;
alter table public.sessions enable row level security;
alter table public.game_scores enable row level security;
alter table public.game_sessions enable row level security;
alter table public.password_reset_tokens enable row level security;
alter table public.auth_rate_limits enable row level security;

-- Políticas explícitamente denegadas para el acceso directo desde la API.
-- No dependen de la identidad JWT de Supabase porque la aplicación utiliza
-- su propio token de sesión; la autorización real vive dentro de las RPC.
drop policy if exists app_users_deny_direct_select on public.app_users;
drop policy if exists app_users_deny_direct_insert on public.app_users;
drop policy if exists app_users_deny_direct_update on public.app_users;
drop policy if exists app_users_deny_direct_delete on public.app_users;
create policy app_users_deny_direct_select on public.app_users for select to anon, authenticated using (false);
create policy app_users_deny_direct_insert on public.app_users for insert to anon, authenticated with check (false);
create policy app_users_deny_direct_update on public.app_users for update to anon, authenticated using (false) with check (false);
create policy app_users_deny_direct_delete on public.app_users for delete to anon, authenticated using (false);

drop policy if exists games_deny_direct_select on public.games;
drop policy if exists games_deny_direct_insert on public.games;
drop policy if exists games_deny_direct_update on public.games;
drop policy if exists games_deny_direct_delete on public.games;
create policy games_deny_direct_select on public.games for select to anon, authenticated using (false);
create policy games_deny_direct_insert on public.games for insert to anon, authenticated with check (false);
create policy games_deny_direct_update on public.games for update to anon, authenticated using (false) with check (false);
create policy games_deny_direct_delete on public.games for delete to anon, authenticated using (false);

drop policy if exists sessions_deny_direct_select on public.sessions;
drop policy if exists sessions_deny_direct_insert on public.sessions;
drop policy if exists sessions_deny_direct_update on public.sessions;
drop policy if exists sessions_deny_direct_delete on public.sessions;
create policy sessions_deny_direct_select on public.sessions for select to anon, authenticated using (false);
create policy sessions_deny_direct_insert on public.sessions for insert to anon, authenticated with check (false);
create policy sessions_deny_direct_update on public.sessions for update to anon, authenticated using (false) with check (false);
create policy sessions_deny_direct_delete on public.sessions for delete to anon, authenticated using (false);

drop policy if exists scores_deny_direct_select on public.game_scores;
drop policy if exists scores_deny_direct_insert on public.game_scores;
drop policy if exists scores_deny_direct_update on public.game_scores;
drop policy if exists scores_deny_direct_delete on public.game_scores;
create policy scores_deny_direct_select on public.game_scores for select to anon, authenticated using (false);
create policy scores_deny_direct_insert on public.game_scores for insert to anon, authenticated with check (false);
create policy scores_deny_direct_update on public.game_scores for update to anon, authenticated using (false) with check (false);
create policy scores_deny_direct_delete on public.game_scores for delete to anon, authenticated using (false);

drop policy if exists game_sessions_deny_direct_select on public.game_sessions;
drop policy if exists game_sessions_deny_direct_insert on public.game_sessions;
drop policy if exists game_sessions_deny_direct_update on public.game_sessions;
drop policy if exists game_sessions_deny_direct_delete on public.game_sessions;
create policy game_sessions_deny_direct_select on public.game_sessions for select to anon, authenticated using (false);
create policy game_sessions_deny_direct_insert on public.game_sessions for insert to anon, authenticated with check (false);
create policy game_sessions_deny_direct_update on public.game_sessions for update to anon, authenticated using (false) with check (false);
create policy game_sessions_deny_direct_delete on public.game_sessions for delete to anon, authenticated using (false);

drop policy if exists password_reset_tokens_deny_direct_select on public.password_reset_tokens;
drop policy if exists password_reset_tokens_deny_direct_insert on public.password_reset_tokens;
drop policy if exists password_reset_tokens_deny_direct_update on public.password_reset_tokens;
drop policy if exists password_reset_tokens_deny_direct_delete on public.password_reset_tokens;
create policy password_reset_tokens_deny_direct_select on public.password_reset_tokens for select to anon, authenticated using (false);
create policy password_reset_tokens_deny_direct_insert on public.password_reset_tokens for insert to anon, authenticated with check (false);
create policy password_reset_tokens_deny_direct_update on public.password_reset_tokens for update to anon, authenticated using (false) with check (false);
create policy password_reset_tokens_deny_direct_delete on public.password_reset_tokens for delete to anon, authenticated using (false);

drop policy if exists auth_rate_limits_deny_direct_select on public.auth_rate_limits;
drop policy if exists auth_rate_limits_deny_direct_insert on public.auth_rate_limits;
drop policy if exists auth_rate_limits_deny_direct_update on public.auth_rate_limits;
drop policy if exists auth_rate_limits_deny_direct_delete on public.auth_rate_limits;
create policy auth_rate_limits_deny_direct_select on public.auth_rate_limits for select to anon, authenticated using (false);
create policy auth_rate_limits_deny_direct_insert on public.auth_rate_limits for insert to anon, authenticated with check (false);
create policy auth_rate_limits_deny_direct_update on public.auth_rate_limits for update to anon, authenticated using (false) with check (false);
create policy auth_rate_limits_deny_direct_delete on public.auth_rate_limits for delete to anon, authenticated using (false);

revoke all on table public.app_users, public.games, public.sessions, public.game_scores, public.game_sessions, public.password_reset_tokens, public.auth_rate_limits, public.game_statistics from anon, authenticated;
revoke all on table public.admin_audit_log from anon, authenticated;

-- ================================================================
-- Matriz final de ejecución: la app usa tokens propios, por ello el
-- rol Supabase de transporte es ANON; la autorización real la realiza
-- _require_session/_require_admin dentro de cada RPC.
-- ================================================================
revoke all on function public.register_user(text,text,text) from public,anon,authenticated;
revoke all on function public.login_user(text,text) from public,anon,authenticated;
revoke all on function public.get_session(text) from public,anon,authenticated;
revoke all on function public.logout_user(text) from public,anon,authenticated;
revoke all on function public.change_password(text,text,text) from public,anon,authenticated;
revoke all on function public.request_password_reset(text) from public,anon,authenticated;
revoke all on function public.reset_password_with_token(text,text) from public,anon,authenticated;
revoke all on function public.revoke_other_sessions(text) from public,anon,authenticated;
revoke all on function public.list_games(text) from public,anon,authenticated;
revoke all on function public.list_game_catalog(text) from public,anon,authenticated;
revoke all on function public.start_game(text,text,text) from public,anon,authenticated;
revoke all on function public.finish_game(text,uuid,integer,jsonb) from public,anon,authenticated;
revoke all on function public.my_scores(text) from public,anon,authenticated;
revoke all on function public.my_game_statistics(text) from public,anon,authenticated;
revoke all on function public.admin_list_users_page(text,integer,integer) from public,anon,authenticated;
revoke all on function public.admin_list_scores_page(text,integer,integer) from public,anon,authenticated;
revoke all on function public.admin_list_sessions_page(text,integer,integer) from public,anon,authenticated;
revoke all on function public.admin_list_audit_page(text,integer,integer) from public,anon,authenticated;
revoke all on function public.admin_list_games(text) from public,anon,authenticated;
revoke all on function public.admin_set_user_role(text,uuid,text) from public,anon,authenticated;
revoke all on function public.admin_set_game_active(text,uuid,boolean) from public,anon,authenticated;

grant execute on function public.register_user(text,text,text) to anon;
grant execute on function public.login_user(text,text) to anon;
grant execute on function public.get_session(text) to anon;
grant execute on function public.logout_user(text) to anon;
grant execute on function public.change_password(text,text,text) to anon;
grant execute on function public.request_password_reset(text) to anon;
grant execute on function public.reset_password_with_token(text,text) to anon;
grant execute on function public.revoke_other_sessions(text) to anon;
grant execute on function public.list_games(text) to anon;
grant execute on function public.list_game_catalog(text) to anon;
grant execute on function public.start_game(text,text,text) to anon;
grant execute on function public.finish_game(text,uuid,integer,jsonb) to anon;
grant execute on function public.my_scores(text) to anon;
grant execute on function public.my_game_statistics(text) to anon;

grant execute on function public.admin_list_users_page(text,integer,integer) to anon;
grant execute on function public.admin_list_scores_page(text,integer,integer) to anon;
grant execute on function public.admin_list_sessions_page(text,integer,integer) to anon;
grant execute on function public.admin_list_audit_page(text,integer,integer) to anon;
grant execute on function public.admin_list_games(text) to anon;
grant execute on function public.admin_set_user_role(text,uuid,text) to anon;
grant execute on function public.admin_set_game_active(text,uuid,boolean) to anon;
