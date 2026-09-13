-- Invariantes de integridad para STAGING.
-- No modifica datos: solo valida invariantes existentes.

select case when count(*) = count(distinct email) then 'PASS' else 'FAIL' end as unique_emails
from public.app_users;

select case when count(*) = count(distinct lower(email)) then 'PASS' else 'FAIL' end as normalized_emails
from public.app_users;

select case when count(*) = 0 then 'PASS' else 'FAIL' end as invalid_session_expiration
from public.sessions
where expires_at <= created_at;

select case when count(*) = 0 then 'PASS' else 'FAIL' end as invalid_game_session_expiration
from public.game_sessions
where expires_at <= started_at;

select case when count(*) = 0 then 'PASS' else 'FAIL' end as duplicate_active_game_sessions
from (
  select user_id, game_id
  from public.game_sessions
  where status = 'active'
  group by user_id, game_id
  having count(*) > 1
) duplicates;

select case when count(*) = 0 then 'PASS' else 'FAIL' end as invalid_score_range
from public.game_scores
where score < 0;
