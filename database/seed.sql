-- Zona de Juegos - Datos iniciales
insert into public.games (slug, name, description, icon, score_ceiling, is_active)
values (
  'snake',
  'SNAKE',
  'Come, crece y sobrevive todo lo que puedas sin chocar contigo mismo.',
  '🐍',
  3970,
  true
)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  score_ceiling = excluded.score_ceiling,
  is_active = excluded.is_active;

-- El registro público siempre crea usuarios normales.
-- Para crear el primer administrador, ejecutar una sola vez database/bootstrap_admin.sql
-- directamente en el SQL Editor de Supabase.
