-- Zona de Juegos - RLS y endurecimiento de permisos

alter table public.app_users enable row level security;
alter table public.games enable row level security;
alter table public.sessions enable row level security;
alter table public.game_scores enable row level security;
alter table public.game_sessions enable row level security;
alter table public.auth_rate_limits enable row level security;
alter table public.password_reset_tokens enable row level security;

-- La aplicación no expone tablas directamente al navegador. Todas las operaciones
-- sensibles pasan por funciones SECURITY DEFINER con validaciones propias.
drop policy if exists app_users_deny_direct_select on public.app_users;
create policy app_users_deny_direct_select on public.app_users for select to anon, authenticated using (false);
drop policy if exists app_users_deny_direct_insert on public.app_users;
create policy app_users_deny_direct_insert on public.app_users for insert to anon, authenticated with check (false);
drop policy if exists app_users_deny_direct_update on public.app_users;
create policy app_users_deny_direct_update on public.app_users for update to anon, authenticated using (false) with check (false);
drop policy if exists app_users_deny_direct_delete on public.app_users;
create policy app_users_deny_direct_delete on public.app_users for delete to anon, authenticated using (false);

drop policy if exists games_deny_direct_select on public.games;
create policy games_deny_direct_select on public.games for select to anon, authenticated using (false);
drop policy if exists games_deny_direct_insert on public.games;
create policy games_deny_direct_insert on public.games for insert to anon, authenticated with check (false);
drop policy if exists games_deny_direct_update on public.games;
create policy games_deny_direct_update on public.games for update to anon, authenticated using (false) with check (false);
drop policy if exists games_deny_direct_delete on public.games;
create policy games_deny_direct_delete on public.games for delete to anon, authenticated using (false);

drop policy if exists sessions_deny_direct_select on public.sessions;
create policy sessions_deny_direct_select on public.sessions for select to anon, authenticated using (false);
drop policy if exists sessions_deny_direct_insert on public.sessions;
create policy sessions_deny_direct_insert on public.sessions for insert to anon, authenticated with check (false);
drop policy if exists sessions_deny_direct_update on public.sessions;
create policy sessions_deny_direct_update on public.sessions for update to anon, authenticated using (false) with check (false);
drop policy if exists sessions_deny_direct_delete on public.sessions;
create policy sessions_deny_direct_delete on public.sessions for delete to anon, authenticated using (false);

drop policy if exists scores_deny_direct_select on public.game_scores;
create policy scores_deny_direct_select on public.game_scores for select to anon, authenticated using (false);
drop policy if exists scores_deny_direct_insert on public.game_scores;
create policy scores_deny_direct_insert on public.game_scores for insert to anon, authenticated with check (false);
drop policy if exists scores_deny_direct_update on public.game_scores;
create policy scores_deny_direct_update on public.game_scores for update to anon, authenticated using (false) with check (false);
drop policy if exists scores_deny_direct_delete on public.game_scores;
create policy scores_deny_direct_delete on public.game_scores for delete to anon, authenticated using (false);

drop policy if exists game_sessions_deny_direct_select on public.game_sessions;
create policy game_sessions_deny_direct_select on public.game_sessions for select to anon, authenticated using (false);
drop policy if exists game_sessions_deny_direct_insert on public.game_sessions;
create policy game_sessions_deny_direct_insert on public.game_sessions for insert to anon, authenticated with check (false);
drop policy if exists game_sessions_deny_direct_update on public.game_sessions;
create policy game_sessions_deny_direct_update on public.game_sessions for update to anon, authenticated using (false) with check (false);
drop policy if exists game_sessions_deny_direct_delete on public.game_sessions;
create policy game_sessions_deny_direct_delete on public.game_sessions for delete to anon, authenticated using (false);

drop policy if exists auth_rate_limits_deny_direct_select on public.auth_rate_limits;
create policy auth_rate_limits_deny_direct_select on public.auth_rate_limits for select to anon, authenticated using (false);
drop policy if exists auth_rate_limits_deny_direct_insert on public.auth_rate_limits;
create policy auth_rate_limits_deny_direct_insert on public.auth_rate_limits for insert to anon, authenticated with check (false);
drop policy if exists auth_rate_limits_deny_direct_update on public.auth_rate_limits;
create policy auth_rate_limits_deny_direct_update on public.auth_rate_limits for update to anon, authenticated using (false) with check (false);
drop policy if exists auth_rate_limits_deny_direct_delete on public.auth_rate_limits;
create policy auth_rate_limits_deny_direct_delete on public.auth_rate_limits for delete to anon, authenticated using (false);


-- Elimina permisos de tabla innecesarios para el frontend.
revoke all on table public.app_users, public.games, public.sessions, public.game_scores, public.game_sessions, public.auth_rate_limits from anon, authenticated;


drop policy if exists password_reset_tokens_deny_direct_select on public.password_reset_tokens;
create policy password_reset_tokens_deny_direct_select on public.password_reset_tokens for select to anon, authenticated using (false);
drop policy if exists password_reset_tokens_deny_direct_insert on public.password_reset_tokens;
create policy password_reset_tokens_deny_direct_insert on public.password_reset_tokens for insert to anon, authenticated with check (false);
drop policy if exists password_reset_tokens_deny_direct_update on public.password_reset_tokens;
create policy password_reset_tokens_deny_direct_update on public.password_reset_tokens for update to anon, authenticated using (false) with check (false);
drop policy if exists password_reset_tokens_deny_direct_delete on public.password_reset_tokens;
create policy password_reset_tokens_deny_direct_delete on public.password_reset_tokens for delete to anon, authenticated using (false);
revoke all on table public.password_reset_tokens from anon, authenticated;
