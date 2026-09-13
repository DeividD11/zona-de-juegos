# Política definitiva de sesiones

- Máximo absoluto: 7 días desde `created_at`.
- Inactividad máxima: 24 horas desde `last_seen_at`.
- Máximo: 5 sesiones activas por usuario.
- Al iniciar una sexta sesión se revoca la sesión activa más antigua.
- Cerrar otras sesiones conserva la sesión actual y revoca las demás inmediatamente.
- Logout revoca inmediatamente el token actual; si el servidor no responde, la sesión local se limpia igualmente.
- Una falla de red no transforma una sesión en inválida. Solo `get_session()` sin usuario válido provoca limpieza local.
- `cleanup_sessions()` elimina expiradas, revocadas antiguas y tokens de recuperación usados/expirados.
- Producción: programar `cleanup_sessions()` cada 15 minutos con `maintenance_setup.sql` y `pg_cron`.

## Rate limiting

`login`, `register`, `password_reset`, `start_game` y `finish_game` usan límites por sujeto, IP disponible y operación global. La IP nunca es la única señal.
