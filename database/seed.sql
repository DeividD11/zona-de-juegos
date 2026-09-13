-- Zona de Juegos - Datos iniciales
insert into public.games (slug, name, description, icon, score_ceiling, current_version, release_status, is_active)
values (
  'snake',
  'SNAKE',
  'Come, crece y sobrevive todo lo que puedas sin chocar contigo mismo.',
  '🐍',
  3970,
  '1.1.0',
  'available',
  true
)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  score_ceiling = excluded.score_ceiling,
  current_version = excluded.current_version,
  release_status = excluded.release_status,
  is_active = excluded.is_active;

-- El registro público siempre crea usuarios normales.
-- Para crear el primer administrador, ejecutar una sola vez database/bootstrap_admin.sql
-- directamente en el SQL Editor de Supabase.

-- Juegos registrados para despliegue progresivo. Se mantienen inactivos hasta publicar su motor.
insert into public.games (slug, name, description, icon, score_ceiling, current_version, release_status, is_active)
values
  ('tetris', 'TETRIS', 'Construye líneas y prepara el tablero para la próxima caída.', '🧱', 0, '0.1.0', 'upcoming', false),
  ('pong', 'PONG', 'El clásico duelo de paletas estará disponible próximamente.', '🏓', 0, '0.1.0', 'upcoming', false),
  ('memory', 'MEMORY', 'Encuentra las parejas y mejora tu memoria.', '🧠', 0, '0.1.0', 'upcoming', false),
  ('minesweeper', 'MINESWEEPER', 'Descubre el tablero evitando las minas.', '💣', 0, '0.1.0', 'upcoming', false)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  score_ceiling = excluded.score_ceiling,
  current_version = excluded.current_version,
  release_status = excluded.release_status,
  is_active = excluded.is_active;
