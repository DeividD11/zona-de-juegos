# Paginación por cursor

Las RPC administrativas `admin_list_users_cursor`, `admin_list_scores_cursor`, `admin_list_sessions_cursor` y `admin_list_audit_cursor` usan un cursor estable compuesto por `(created_at, id)` y devuelven `next_cursor` + `has_more`.

Las RPC `*_page` basadas en OFFSET se conservan como compatibilidad y migración gradual. En volúmenes grandes, los consumidores pueden adoptar los endpoints cursor sin cambiar las tablas del dominio.
