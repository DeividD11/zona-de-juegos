-- Reparación de la migración 004.
-- La versión v6 contenía una línea de texto fuera de un comentario que provocaba:
-- ERROR 42601: syntax error at or near "integridad".
-- Esta migración no necesita ejecutarse en una base donde migration_004 ya fue corregida.
-- Se deja como registro documental de la corrección.

-- No-op intencional.
select 1;
