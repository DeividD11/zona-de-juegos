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
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('success', true);
  end if;

  perform public._consume_operation_limits('password_reset', null, v_email);

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
    'score', p_score,
    'game_version', v_game_session.game_version
  );
end;
$$;

revoke all on function public.register_user(text,text,text) from public,anon,authenticated;
grant execute on function public.register_user(text,text,text) to anon;
revoke all on function public.login_user(text,text) from public,anon,authenticated;
grant execute on function public.login_user(text,text) to anon;
revoke all on function public.request_password_reset(text) from public,anon,authenticated;
grant execute on function public.request_password_reset(text) to anon;
revoke all on function public.start_game(text,text,text) from public,anon,authenticated;
grant execute on function public.start_game(text,text,text) to anon;
revoke all on function public.finish_game(text,uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.finish_game(text,uuid,integer,jsonb) to anon;
