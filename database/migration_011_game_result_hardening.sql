-- Migration 011: hardening de game sessions y resultados.
-- Idempotente: valida metadata, duración, score_ceiling, single-use y anti-spam.

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
grant execute on function public.start_game(text, text, text) to anon;
grant execute on function public.finish_game(text, uuid, integer, jsonb) to anon;
