# Testing

La aplicación no añade Node, PHP, Python, React ni frameworks de test. La suite de frontend se ejecuta en el navegador mediante ES Modules y una página estática.

## Suite local

Sirve la raíz del proyecto con un servidor estático y abre:

`tests/test.html`

La suite cubre:

- validaciones de email, contraseña, nombre, score y slug;
- coincidencia de contraseñas;
- autorización USER vs ADMIN;
- registro, login correcto, contraseña incorrecta, sesión inválida/expirada y logout mediante un API mock;
- colisión con pared, comida, crecimiento, score, cola de direcciones y máximo teórico de SNAKE.

## Suite SQL en staging

Ejecuta primero `database/tests/integrity_invariants.sql`.

Después, en `database/tests/security_authorization_tests.sql`, sustituye los cuatro marcadores por tokens/UUID de cuentas de prueba y un juego de staging. El script valida que un USER no pueda:

- cambiar roles;
- modificar juegos;
- listar usuarios mediante RPC administrativas;

y que un ADMIN sí pueda ejecutar una consulta administrativa permitida.

## Concurrencia

La concurrencia real debe probarse contra PostgreSQL en staging, no simularse desde la UI. Casos mínimos:

1. Lanzar dos logins simultáneos del mismo usuario: el total de sesiones activas debe permanecer en `<= 5`.
2. Ejecutar dos cambios concurrentes del último administrador: como máximo una operación debe poder quitar el último rol admin; siempre debe quedar al menos un admin activo.
3. Finalizar dos partidas simultáneamente: las puntuaciones deben quedar asociadas a sus `game_session_id` y las estadísticas agregadas deben coincidir con los resultados persistidos.

Las RPC existentes usan locks transaccionales para estas invariantes. Verifica el resultado con:

```sql
select user_id, count(*) as active_sessions
from public.sessions
where revoked_at is null
  and expires_at > now()
  and last_seen_at > now() - interval '24 hours'
group by user_id
having count(*) > 5;
```

Debe devolver cero filas.

Para una prueba de carga/concurrencia de producción, usa una herramienta externa de PostgreSQL como `pgbench` sobre staging. Esta herramienta es solo de testing y no forma parte de la aplicación desplegada.
