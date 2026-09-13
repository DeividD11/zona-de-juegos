-- Migration 012: auditoría, recuperación de contraseña por correo y paginación cursor.
-- Requiere Supabase Vault + pg_net para el envío real de correo.

create extension if not exists supabase_vault with schema vault;
create extension if not exists pg_net;

-- ================================================================
-- Auditoría administrativa: registrar actor/acción/objetivo/resultado.
-- ================================================================
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
  if p_actor is null or p_action is null or p_target_type is null or p_target_id is null or p_result is null then
    raise exception using errcode='22023', message='Datos de auditoría incompletos.';
  end if;
  if p_target_type not in ('USER','GAME') then
    raise exception using errcode='22023', message='Tipo de objetivo de auditoría no válido.';
  end if;
  if p_result not in ('success','error') then
    raise exception using errcode='22023', message='Resultado de auditoría no válido.';
  end if;
  if octet_length(convert_to(coalesce(p_metadata,'{}'::jsonb)::text,'utf8')) > 4096 then
    raise exception using errcode='22023', message='Metadata de auditoría demasiado grande.';
  end if;

  insert into public.admin_audit_log(admin_user_id, action, target_type, target_id, occurred_at, result, metadata)
  values (p_actor, p_action, p_target_type, p_target_id, now(), p_result, coalesce(p_metadata,'{}'::jsonb));
end;
$$;

revoke all on function public._admin_audit(uuid,text,text,uuid,text,jsonb) from public, anon, authenticated;

-- ================================================================
-- Recuperación real de contraseña por correo.
-- Las claves se almacenan en Supabase Vault, nunca en el frontend/SQL del repo.
-- El envío usa pg_net -> Resend API, por lo que no se agrega un backend propio.
-- Configuración requerida: password_reset_resend_api_key,
-- password_reset_from_email, password_reset_app_url.
-- ================================================================
create or replace function public._send_password_reset_email(
  p_recipient text,
  p_token text
)
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_api_key text;
  v_from text;
  v_app_url text;
  v_request_id bigint;
begin
  select decrypted_secret into v_api_key
  from vault.decrypted_secrets
  where name = 'password_reset_resend_api_key'
  limit 1;

  select decrypted_secret into v_from
  from vault.decrypted_secrets
  where name = 'password_reset_from_email'
  limit 1;

  select decrypted_secret into v_app_url
  from vault.decrypted_secrets
  where name = 'password_reset_app_url'
  limit 1;

  if nullif(trim(v_api_key),'') is null
     or nullif(trim(v_from),'') is null
     or nullif(trim(v_app_url),'') is null then
    raise exception using errcode='55000', message='El servicio de recuperación de contraseña no está configurado.';
  end if;

  v_request_id := net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_api_key
    ),
    body := jsonb_build_object(
      'from', v_from,
      'to', jsonb_build_array(p_recipient),
      'subject', 'Recuperación de contraseña',
      'text', 'Solicitaste restablecer tu contraseña. Abre este enlace para continuar: ' || rtrim(v_app_url, '/') || '?token=' || p_token || '. El enlace vence en 30 minutos.',
      'html', '<p>Solicitaste restablecer tu contraseña.</p><p><a href="' || rtrim(v_app_url, '/') || '?token=' || p_token || '">Restablecer contraseña</a></p><p>El enlace vence en 30 minutos. Si no solicitaste el cambio, puedes ignorar este mensaje.</p>'
    ),
    timeout_milliseconds := 2000
  );

  if v_request_id is null then
    raise exception using errcode='55000', message='No se pudo encolar el correo de recuperación.';
  end if;
end;
$$;

revoke all on function public._send_password_reset_email(text,text) from public, anon, authenticated;

create or replace function public.request_password_reset(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, vault
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

  select * into v_user
  from public.app_users
  where email = v_email and is_active = true
  limit 1;

  if found then
    delete from public.password_reset_tokens where user_id = v_user.id and used_at is null;
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.password_reset_tokens(user_id, token_hash, expires_at)
    values (v_user.id, extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), now() + interval '30 minutes');

    -- El token se entrega únicamente al proveedor de correo; nunca se devuelve al cliente.
    perform public._send_password_reset_email(v_user.email, v_token);
  end if;

  -- Respuesta uniforme para no filtrar si el correo existe.
  return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.request_password_reset(text) from public, anon, authenticated;
grant execute on function public.request_password_reset(text) to anon;

-- ================================================================
-- Paginación por cursor. Las RPC *_page existentes permanecen como compatibilidad.
-- Cursor = created_at + id codificados en base64url.
-- ================================================================
create or replace function public._encode_cursor(p_created_at timestamptz, p_id uuid)
returns text
language sql immutable
security definer
set search_path = public, extensions
as $$
  select replace(replace(rtrim(encode(convert_to(to_char(p_created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || p_id::text,'utf8'),'base64'),'='),'+','-'),'/', '_');
$$;
revoke all on function public._encode_cursor(timestamptz,uuid) from public, anon, authenticated;

create or replace function public._decode_cursor(p_cursor text)
returns table(created_at timestamptz, id uuid)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_raw text;
  v_parts text[];
begin
  if nullif(trim(p_cursor),'') is null then return; end if;
  v_raw := convert_from(decode(replace(replace(p_cursor,'-','+'),'_','/') || repeat('=', (4 - length(p_cursor) % 4) % 4),'base64'),'utf8');
  v_parts := string_to_array(v_raw,'|');
  if array_length(v_parts,1) <> 2 then
    raise exception using errcode='22023', message='Cursor no válido.';
  end if;
  created_at := v_parts[1]::timestamptz;
  id := v_parts[2]::uuid;
  return next;
exception
  when others then
    raise exception using errcode='22023', message='Cursor no válido.';
end;
$$;
revoke all on function public._decode_cursor(text) from public, anon, authenticated;

create or replace function public.admin_list_users_cursor(
  p_session_token text,
  p_cursor text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_limit integer := least(100,greatest(1,coalesce(p_limit,20)));
  v_cur timestamptz;
  v_id uuid;
  v_rows jsonb;
  v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then
    select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1;
  end if;

  with rows as (
    select id,display_name,email,role,is_active,created_at
    from public.app_users
    where v_cur is null or (created_at,id) < (v_cur,v_id)
    order by created_at desc,id desc
    limit v_limit + 1
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]'::jsonb),
         (select public._encode_cursor(created_at,id) from rows order by created_at asc,id asc offset 1 limit 1)
  into v_rows,v_next
  from rows r;

  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows) > v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n <= v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

create or replace function public.admin_list_scores_cursor(p_session_token text,p_cursor text default null,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_cur timestamptz; v_id uuid; v_rows jsonb; v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1; end if;
  with rows as (select gs.id,u.display_name,u.email,g.name as game_name,g.slug,gs.score,gs.created_at from public.game_scores gs join public.app_users u on u.id=gs.user_id join public.games g on g.id=gs.game_id where v_cur is null or (gs.created_at,gs.id)<(v_cur,v_id) order by gs.created_at desc,gs.id desc limit v_limit+1)
  select coalesce(jsonb_agg(row_to_json(r) order by r.created_at desc,r.id desc),'[]'::jsonb),(select public._encode_cursor(created_at,id) from rows order by created_at asc,id asc offset 1 limit 1) into v_rows,v_next from rows r;
  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows)>v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n<=v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

create or replace function public.admin_list_sessions_cursor(p_session_token text,p_cursor text default null,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_cur timestamptz; v_id uuid; v_rows jsonb; v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1; end if;
  with rows as (select s.id,u.display_name,u.email,s.created_at,s.expires_at,s.revoked_at,s.last_seen_at from public.sessions s join public.app_users u on u.id=s.user_id where v_cur is null or (s.created_at,s.id)<(v_cur,v_id) order by s.created_at desc,s.id desc limit v_limit+1)
  select coalesce(jsonb_agg(row_to_json(r) order by r.created_at desc,r.id desc),'[]'::jsonb),(select public._encode_cursor(created_at,id) from rows order by created_at asc,id asc offset 1 limit 1) into v_rows,v_next from rows r;
  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows)>v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n<=v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

create or replace function public.admin_list_audit_cursor(p_session_token text,p_cursor text default null,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,20))); v_cur timestamptz; v_id uuid; v_rows jsonb; v_next text;
begin
  perform public._require_admin(p_session_token);
  if nullif(trim(p_cursor),'') is not null then select created_at,id into v_cur,v_id from public._decode_cursor(p_cursor) limit 1; end if;
  with rows as (select a.id,au.display_name as admin_name,a.action,a.target_type,a.target_id,a.occurred_at,a.result,a.metadata from public.admin_audit_log a left join public.app_users au on au.id=a.admin_user_id where v_cur is null or (a.occurred_at,a.id)<(v_cur,v_id) order by a.occurred_at desc,a.id desc limit v_limit+1)
  select coalesce(jsonb_agg(row_to_json(r) order by r.occurred_at desc,r.id desc),'[]'::jsonb),(select public._encode_cursor(occurred_at,id) from rows order by occurred_at asc,id asc offset 1 limit 1) into v_rows,v_next from rows r;
  return jsonb_build_object('limit',v_limit,'data',case when jsonb_array_length(v_rows)>v_limit then (select jsonb_agg(x) from jsonb_array_elements(v_rows) with ordinality t(x,n) where n<=v_limit) else v_rows end,'next_cursor',case when jsonb_array_length(v_rows)>v_limit then v_next else null end,'has_more',jsonb_array_length(v_rows)>v_limit);
end; $$;

revoke all on function public.admin_list_users_cursor(text,text,integer) from public,anon,authenticated;
revoke all on function public.admin_list_scores_cursor(text,text,integer) from public,anon,authenticated;
revoke all on function public.admin_list_sessions_cursor(text,text,integer) from public,anon,authenticated;
revoke all on function public.admin_list_audit_cursor(text,text,integer) from public,anon,authenticated;
grant execute on function public.admin_list_users_cursor(text,text,integer) to anon;
grant execute on function public.admin_list_scores_cursor(text,text,integer) to anon;
grant execute on function public.admin_list_sessions_cursor(text,text,integer) to anon;
grant execute on function public.admin_list_audit_cursor(text,text,integer) to anon;
