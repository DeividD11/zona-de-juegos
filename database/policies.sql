-- Compatibilidad para instalaciones antiguas.
-- La instalación desde cero ya incluye RLS, políticas y REVOKE en schema.sql.
-- Este archivo puede ejecutarse después del esquema para re-aplicar las mismas
-- políticas sin crear duplicados.

alter table public.app_users enable row level security;
alter table public.games enable row level security;
alter table public.sessions enable row level security;
alter table public.game_scores enable row level security;
alter table public.game_sessions enable row level security;
alter table public.auth_rate_limits enable row level security;
alter table public.password_reset_tokens enable row level security;
alter table public.game_statistics enable row level security;
alter table public.admin_audit_log enable row level security;

revoke all on table public.app_users, public.games, public.sessions, public.game_scores, public.game_sessions, public.auth_rate_limits, public.password_reset_tokens, public.game_statistics, public.admin_audit_log from anon, authenticated;
