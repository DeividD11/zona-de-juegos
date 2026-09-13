-- ================================================================
-- Migration 007: catálogo de juegos y estados de disponibilidad
-- ================================================================
-- Ejecutar después de migration_006_security_dto.sql.
-- Es idempotente.

alter table public.games
  add column if not exists release_status text not null default 'available';

update public.games
set release_status = 'available'
where release_status is null
   or release_status not in ('available', 'upcoming');

alter table public.games
  drop constraint if exists games_release_status_check;

alter table public.games
  add constraint games_release_status_check
  check (release_status in ('available', 'upcoming'));

create or replace function public.list_game_catalog(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
begin
  select user_id
  into v_user_id
  from public._require_session(p_session_token)
  limit 1;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', g.id,
        'slug', g.slug,
        'name', g.name,
        'description', g.description,
        'icon', g.icon,
        'score_ceiling', g.score_ceiling,
        'current_version', g.current_version,
        'release_status', case
          when not g.is_active then 'disabled'
          else g.release_status
        end,
        'is_active', g.is_active,
        'best_score', coalesce((
          select max(gs.score)
          from public.game_scores gs
          where gs.user_id = v_user_id
            and gs.game_id = g.id
        ), 0)
      )
      order by
        case
          when g.is_active and g.release_status = 'available' then 0
          when g.is_active and g.release_status = 'upcoming' then 1
          else 2
        end,
        g.name
    )
    from public.games g
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_game_catalog(text) from public;
grant execute on function public.list_game_catalog(text) to anon, authenticated;

comment on function public.list_game_catalog(text)
is 'Catálogo mínimo para dashboard, incluyendo estado, versión y mejor puntuación.';
