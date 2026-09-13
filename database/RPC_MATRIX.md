# Matriz de RPC y autorización

La aplicación usa autenticación propia con tokens. Por eso Supabase recibe las llamadas mediante el rol de transporte `anon`; el rol de aplicación (`user`/`admin`) se determina dentro de PostgreSQL con `_require_session()` y `_require_admin()`.

| RPC | Público/USER/ADMIN | Validación | DTO mínimo |
|---|---|---|---|
| `register_user` | PUBLIC | argumentos + rate limit; fuerza `role=user` | sesión + perfil mínimo |
| `login_user` | PUBLIC | credenciales + rate limit | sesión + perfil mínimo |
| `request_password_reset` | PUBLIC | email + rate limit; respuesta uniforme | `{success}` |
| `reset_password_with_token` | PUBLIC | token + expiración + cuenta activa | `{success, revoked_sessions}` |
| `get_session` | USER/ADMIN | token + sesión + usuario activo | `id,name,email,role` |
| `logout_user` | USER/ADMIN | hash del token | boolean |
| `change_password` | USER/ADMIN | token + propiedad + contraseña actual | `{success, revoked_sessions}` |
| `revoke_other_sessions` | USER/ADMIN | token + propia cuenta | `{success, revoked_sessions}` |
| `list_games` / `list_game_catalog` | USER/ADMIN | sesión válida | catálogo mínimo |
| `start_game` | USER/ADMIN | sesión + juego activo + versión | sesión de partida mínima |
| `finish_game` | USER/ADMIN | sesión + propiedad + score + reglas antifraude | resultado mínimo |
| `my_scores` / `my_game_statistics` | USER/ADMIN | sesión válida + propiedad propia | historial/agregados mínimos |
| `admin_*` | ADMIN | `_require_admin()` antes de operar | páginas/resultado mínimo |

## Regla de orden de seguridad

Todas las RPC protegidas deben seguir: validar argumentos → token → sesión → usuario → rol → propiedad/recurso → reglas de negocio → operación → DTO mínimo.

Las restricciones RLS/GRANT complementan esta defensa y nunca la sustituyen.

### Recuperación real

`request_password_reset` genera un token de un solo uso, almacena solo su hash y envía el enlace de forma asíncrona mediante `pg_net` a Resend. La respuesta al navegador sigue siendo uniforme (`{success:true}`) para evitar enumeración de cuentas. Las credenciales de correo viven en Supabase Vault.

### Paginación cursor

`admin_list_users_cursor`, `admin_list_scores_cursor`, `admin_list_sessions_cursor` y `admin_list_audit_cursor` devuelven DTOs mínimos y un cursor estable basado en fecha + UUID. Las RPC de página mediante OFFSET quedan como compatibilidad.
