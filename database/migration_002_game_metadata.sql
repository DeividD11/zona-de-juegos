-- Migración 002 (compatibilidad): columnas y datos base de metadatos.
-- No elimina RPC nuevas. Las RPC se instalan/reparan en migration_003_repair_game_rpcs.sql.

alter table public.game_sessions
  add column if not exists game_version text not null default '1.0.0';

alter table public.game_sessions
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.games
set score_ceiling = ((20 * 20) - 3) * 10
where slug = 'snake';
