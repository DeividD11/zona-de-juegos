-- Ejecutar una vez en producción después de habilitar pg_cron en Supabase.
create extension if not exists pg_cron;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname='zona-juegos-cleanup-sessions';
exception when undefined_table then null; end $$;
select cron.schedule('zona-juegos-cleanup-sessions','*/15 * * * *',$$select public.cleanup_sessions();$$);
