-- ================================================================
-- Migration 008: estadísticas y preparación de leaderboards
-- ================================================================
-- Ejecutar después de migration_007_game_catalog.sql.
-- Es idempotente.
--
-- game_scores = resultados inmutables/históricos.
-- game_statistics = agregados por usuario y juego.
-- leaderboard_* = vistas derivadas para ranking global/semanal/mensual.

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
  p_user_id uuid,
  p_game_id uuid,
  p_score integer,
  p_played_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.game_statistics(
    user_id, game_id, games_played, total_score, best_score, last_played_at, updated_at
  )
  values (
    p_user_id, p_game_id, 1, p_score, p_score, p_played_at, now()
  )
  on conflict (user_id, game_id) do update
  set games_played = public.game_statistics.games_played + 1,
      total_score = public.game_statistics.total_score + excluded.total_score,
      best_score = greatest(public.game_statistics.best_score, excluded.best_score),
      last_played_at = greatest(public.game_statistics.last_played_at, excluded.last_played_at),
      updated_at = now();
end;
$$;

revoke all on function public.refresh_game_statistics(uuid, uuid, integer, timestamptz)
from public, anon, authenticated;

-- Backfill seguro desde resultados existentes.
insert into public.game_statistics(
  user_id, game_id, games_played, total_score, best_score, last_played_at, updated_at
)
select
  gs.user_id,
  gs.game_id,
  count(*)::integer,
  coalesce(sum(gs.score), 0),
  coalesce(max(gs.score), 0),
  max(gs.created_at),
  now()
from public.game_scores gs
group by gs.user_id, gs.game_id
on conflict (user_id, game_id) do update
set games_played = excluded.games_played,
    total_score = excluded.total_score,
    best_score = excluded.best_score,
    last_played_at = excluded.last_played_at,
    updated_at = now();

create or replace view public.leaderboard_global as
select
  s.game_id,
  g.slug as game_slug,
  g.name as game_name,
  s.user_id,
  u.display_name,
  s.best_score,
  s.games_played,
  s.last_played_at,
  dense_rank() over (
    partition by s.game_id
    order by s.best_score desc, s.last_played_at asc nulls last, s.user_id
  ) as ranking_position
from public.game_statistics s
join public.games g on g.id = s.game_id
join public.app_users u on u.id = s.user_id
where u.is_active = true and g.is_active = true;

create or replace view public.leaderboard_weekly as
select
  gs.game_id,
  g.slug as game_slug,
  g.name as game_name,
  gs.user_id,
  u.display_name,
  max(gs.score) as best_score,
  count(*)::integer as games_played,
  max(gs.created_at) as last_played_at,
  dense_rank() over (
    partition by gs.game_id
    order by max(gs.score) desc, max(gs.created_at) asc, gs.user_id
  ) as ranking_position
from public.game_scores gs
join public.games g on g.id = gs.game_id
join public.app_users u on u.id = gs.user_id
where gs.created_at >= date_trunc('week', now())
  and u.is_active = true
  and g.is_active = true
group by gs.game_id, g.slug, g.name, gs.user_id, u.display_name;

create or replace view public.leaderboard_monthly as
select
  gs.game_id,
  g.slug as game_slug,
  g.name as game_name,
  gs.user_id,
  u.display_name,
  max(gs.score) as best_score,
  count(*)::integer as games_played,
  max(gs.created_at) as last_played_at,
  dense_rank() over (
    partition by gs.game_id
    order by max(gs.score) desc, max(gs.created_at) asc, gs.user_id
  ) as ranking_position
from public.game_scores gs
join public.games g on g.id = gs.game_id
join public.app_users u on u.id = gs.user_id
where gs.created_at >= date_trunc('month', now())
  and u.is_active = true
  and g.is_active = true
group by gs.game_id, g.slug, g.name, gs.user_id, u.display_name;

-- Privilegios de las vistas: se expondrán en el futuro mediante una RPC mínima.
revoke all on public.leaderboard_global from public, anon, authenticated;
revoke all on public.leaderboard_weekly from public, anon, authenticated;
revoke all on public.leaderboard_monthly from public, anon, authenticated;

create or replace function public.my_game_statistics(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from public._require_session(p_session_token)
  limit 1;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'slug', g.slug,
        'game_name', g.name,
        'games_played', s.games_played,
        'total_score', s.total_score,
        'best_score', s.best_score,
        'last_played_at', s.last_played_at
      )
      order by s.best_score desc, g.name
    )
    from public.game_statistics s
    join public.games g on g.id = s.game_id
    where s.user_id = v_user_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.my_game_statistics(text) from public, anon, authenticated;
grant execute on function public.my_game_statistics(text) to anon, authenticated;

-- Encima de la tabla de resultados, mantener estadísticas en sincronía.
create or replace function public.sync_game_statistics_after_score()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public.refresh_game_statistics(new.user_id, new.game_id, new.score, new.created_at);
  return new;
end;
$$;

drop trigger if exists trg_sync_game_statistics on public.game_scores;
create trigger trg_sync_game_statistics
after insert on public.game_scores
for each row execute function public.sync_game_statistics_after_score();

revoke all on function public.sync_game_statistics_after_score() from public, anon, authenticated;


-- La consulta del Dashboard puede leer el agregado estable en lugar de recalcular
-- max()/group by sobre todo el historial en cada visita.
create or replace function public.my_scores(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from public._require_session(p_session_token)
  limit 1;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'slug', g.slug,
        'game_name', g.name,
        'best_score', s.best_score,
        'last_played', s.last_played_at
      )
      order by s.best_score desc, g.name
    )
    from public.game_statistics s
    join public.games g on g.id = s.game_id
    where s.user_id = v_user_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.my_scores(text) from public, anon, authenticated;
grant execute on function public.my_scores(text) to anon, authenticated;
