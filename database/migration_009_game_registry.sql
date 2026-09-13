-- ================================================================
-- Migration 009: registrar nuevos juegos sin tocar el núcleo
-- ================================================================
-- La arquitectura del frontend solo necesita una nueva entrada de
-- GameRegistry + su módulo. Estos registros permanecen inactivos hasta
-- que exista una implementación de juego publicada.

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
