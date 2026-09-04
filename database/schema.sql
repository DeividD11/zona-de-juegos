-- Zona de Juegos - Schema
-- Ejecutar en el SQL Editor de Supabase.

create extension if not exists pgcrypto with schema extensions;

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

update public.games
set score_ceiling = 3970
where slug = 'snake' and (score_ceiling is null or score_ceiling > 3970);

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
  created_at timestamptz not null default now()
);

create index if not exists idx_game_sessions_user_game on public.game_sessions(user_id, game_id, created_at desc);
create index if not exists idx_game_sessions_active on public.game_sessions(user_id, game_id, status);
create index if not exists idx_game_sessions_user_status_time on public.game_sessions(user_id, status, finished_at desc);

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
  v_client text;
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

  -- 2. Registrar intento / protección antiabuso
  v_client := public._request_identity(v_email);
  perform public._rate_limit_check('register', v_client, 5, interval '1 hour');

  insert into public.app_users(display_name, email, password_hash, role)
  values (
    trim(p_display_name),
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    'user'
  )
  returning * into v_user;

  perform public._rate_limit_record('register', v_client, interval '1 hour', interval '15 minutes');

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
  v_client text;
  v_key text;
  v_active_sessions integer;
begin
  -- 1. Validar entrada
  v_email := lower(trim(coalesce(p_email, '')));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or nullif(p_password, '') is null then
    raise exception using errcode = '28000', message = 'Correo o contraseña incorrectos.';
  end if;

  -- 2. Protección antiabuso
  v_client := public._request_identity(v_email);
  v_key := v_email || ':' || encode(extensions.digest(convert_to(v_client, 'utf8'), 'sha256'), 'hex');
  perform public._rate_limit_check('login', v_key, 5, interval '15 minutes');

  -- 3. Buscar y validar credenciales
  select * into v_user
  from public.app_users
  where email = v_email
    and is_active = true;

  if not found or not (v_user.password_hash = extensions.crypt(p_password, v_user.password_hash)) then
    perform public._rate_limit_record('login', v_key, interval '15 minutes', interval '30 seconds');
    raise exception using errcode = '28000', message = 'Correo o contraseña incorrectos.';
  end if;

  perform public._rate_limit_reset('login', v_key);

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
    'display_name', v_row.display_name,
    'email', v_row.email,
    'role', v_row.role,
    'is_active', v_row.is_active,
    'created_at', v_row.created_at,
    'expires_at', v_row.expires_at
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

create or replace function public.request_password_reset(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_user public.app_users;
  v_token text;
  v_client text;
  v_key text;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('success', true);
  end if;

  v_client := public._request_identity(v_email);
  v_key := 'reset:' || v_email || ':' || encode(extensions.digest(convert_to(v_client, 'utf8'), 'sha256'), 'hex');
  perform public._rate_limit_check('password-reset', v_key, 3, interval '1 hour');
  perform public._rate_limit_record('password-reset', v_key, interval '1 hour', interval '15 minutes');

  select * into v_user from public.app_users where email = v_email and is_active = true limit 1;
  if found then
    delete from public.password_reset_tokens where user_id = v_user.id and used_at is null;
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.password_reset_tokens(user_id, token_hash, expires_at)
    values (v_user.id, extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), now() + interval '30 minutes');
    -- La función no devuelve el token para no convertirla en un canal de fuga de credenciales.
    -- Un proveedor de correo/automatización externo debe leer el evento de recuperación y enviar el enlace.
  end if;

  return jsonb_build_object('success', true);
end;
$$;

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
    select jsonb_agg(to_jsonb(g) order by g.name)
    from public.games g
    where g.is_active = true
  ), '[]'::jsonb);
end;
$$;

drop function if exists public.save_score(text, text, integer);

create or replace function public.start_game(
  p_session_token text,
  p_game_slug text
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
  select id, slug, score_ceiling into v_game
  from public.games
  where slug = lower(trim(p_game_slug)) and is_active = true;
  if v_game.id is null then
    raise exception using errcode = '22023', message = 'El juego no está disponible.';
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

  insert into public.game_sessions(user_id, game_id, expires_at)
  values (v_user_id, v_game.id, now() + interval '15 minutes')
  returning * into v_session;

  return jsonb_build_object(
    'game_session_id', v_session.id,
    'game_slug', v_game.slug,
    'started_at', v_session.started_at,
    'expires_at', v_session.expires_at
  );
end;
$$;

create or replace function public.finish_game(
  p_session_token text,
  p_game_session_id uuid,
  p_score integer
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

  if v_recent_scores >= 20 then
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

  update public.game_sessions
  set status = 'completed', finished_at = now(), score = p_score
  where id = v_game_session.id;

  insert into public.game_scores(user_id, game_id, score)
  values (v_user_id, v_game_session.game_id, p_score);

  select max(score) into v_best
  from public.game_scores
  where user_id = v_user_id and game_id = v_game_session.game_id;

  return jsonb_build_object(
    'score', p_score,
    'best_score', coalesce(v_best, p_score),
    'game_session_id', v_game_session.id
  );
end;
$$;

revoke all on function public.start_game(text, text) from public, anon, authenticated;
revoke all on function public.finish_game(text, uuid, integer) from public, anon, authenticated;

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

create or replace function public.admin_get_data(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor record;
  v_users jsonb;
  v_games jsonb;
begin
  -- 1. Validar sesión y rol
  select * into v_actor from public._require_admin(p_session_token) limit 1;

  select coalesce(jsonb_agg(to_jsonb(u) - 'password_hash' order by u.created_at desc), '[]'::jsonb)
  into v_users from public.app_users u;

  select coalesce(jsonb_agg(to_jsonb(g) order by g.name), '[]'::jsonb)
  into v_games from public.games g;

  return jsonb_build_object('users', v_users, 'games', v_games);
end;
$$;

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
  -- 1. Validar entrada
  if p_user_id is null or p_role is null then
    raise exception using errcode = '22023', message = 'Datos de rol no válidos.';
  end if;

  -- 2. Validar sesión y rol
  select * into v_actor from public._require_admin(p_session_token) limit 1;

  -- 3. Serializar cambio de privilegios
  perform pg_advisory_xact_lock(hashtextextended('zona-de-juegos-admin-role-change', 0));

  if p_role not in ('admin', 'user') then
    raise exception using errcode = '22023', message = 'Rol no válido.';
  end if;

  select role into v_current_role from public.app_users where id = p_user_id;
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
begin
  -- 1. Validar entrada
  if p_game_id is null or p_is_active is null then
    raise exception using errcode = '22023', message = 'Datos de juego no válidos.';
  end if;

  -- 2. Validar sesión y rol
  perform public._require_admin(p_session_token);

  -- 3. Ejecutar operación autorizada
  update public.games set is_active = p_is_active where id = p_game_id;
  if not found then
    raise exception using errcode = '22023', message = 'Juego no encontrado.';
  end if;

  return jsonb_build_object('success', true, 'game_id', p_game_id, 'is_active', p_is_active);
end;
$$;

-- Permisos RPC: el frontend usa solamente funciones explícitamente expuestas.
grant execute on function public.register_user(text, text, text) to anon, authenticated;
grant execute on function public.login_user(text, text) to anon, authenticated;
grant execute on function public.get_session(text) to anon, authenticated;
grant execute on function public.logout_user(text) to anon, authenticated;
grant execute on function public.change_password(text, text, text) to anon, authenticated;
grant execute on function public.request_password_reset(text) to anon, authenticated;
grant execute on function public.reset_password_with_token(text, text) to anon, authenticated;
grant execute on function public.revoke_other_sessions(text) to anon, authenticated;
grant execute on function public.list_games(text) to anon, authenticated;
grant execute on function public.start_game(text, text) to anon, authenticated;
grant execute on function public.finish_game(text, uuid, integer) to anon, authenticated;
grant execute on function public.my_scores(text) to anon, authenticated;
grant execute on function public.admin_get_data(text) to anon, authenticated;
grant execute on function public.admin_set_user_role(text, uuid, text) to anon, authenticated;
grant execute on function public.admin_set_game_active(text, uuid, boolean) to anon, authenticated;

