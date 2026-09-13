-- Migration 013: corrige la sintaxis de _admin_audit de migration_012.
-- PostgreSQL no permite declarar parámetros de funciones como NOT NULL.
-- La obligatoriedad se valida dentro del cuerpo de la función.

create or replace function public._admin_audit(
  p_actor uuid,
  p_action text,
  p_target_type text,
  p_target_id uuid,
  p_result text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_actor is null
     or p_action is null
     or p_target_type is null
     or p_target_id is null
     or p_result is null then
    raise exception using
      errcode = '22023',
      message = 'Datos de auditoría incompletos.';
  end if;

  if p_target_type not in ('USER', 'GAME') then
    raise exception using
      errcode = '22023',
      message = 'Tipo de objetivo de auditoría no válido.';
  end if;

  if p_result not in ('success', 'error') then
    raise exception using
      errcode = '22023',
      message = 'Resultado de auditoría no válido.';
  end if;

  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'La metadata de auditoría debe ser un objeto JSON.';
  end if;

  if octet_length(convert_to(coalesce(p_metadata, '{}'::jsonb)::text, 'utf8')) > 4096 then
    raise exception using
      errcode = '22023',
      message = 'Metadata de auditoría demasiado grande.';
  end if;

  insert into public.admin_audit_log(
    admin_user_id,
    action,
    target_type,
    target_id,
    occurred_at,
    result,
    metadata
  )
  values (
    p_actor,
    p_action,
    p_target_type,
    p_target_id,
    now(),
    p_result,
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

revoke all on function public._admin_audit(uuid, text, text, uuid, text, jsonb)
from public, anon, authenticated;
