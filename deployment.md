# Estrategia de despliegue

## Development

- Host local: `localhost` / `127.0.0.1`.
- HTTP permitido únicamente para desarrollo local.
- Usar datos de prueba y verificar migraciones antes de compartir el entorno.

## Staging

- Host recomendado: `staging.<dominio>`.
- HTTPS obligatorio.
- Supabase y datos de staging separados de producción.
- Validar migraciones, RPC, CSP y navegación antes de publicar.

## Production

- HTTPS obligatorio.
- HSTS con `includeSubDomains`.
- CSP estricta, sin JavaScript ni CSS inline.
- `X-Content-Type-Options: nosniff`.
- `Referrer-Policy: strict-origin-when-cross-origin`.
- `Permissions-Policy` restrictiva.
- `X-Frame-Options: DENY` y `frame-ancestors 'none'`.

## Selección del entorno

`js/config/app.config.js` determina automáticamente `development`, `staging` o `production` por hostname. En un hosting controlado también puede definirse `window.__APP_ENV__` desde un archivo JavaScript externo antes del módulo de página.

No se almacenan secretos de servidor en el frontend. La credencial de Supabase usada por el navegador es publicable; las operaciones sensibles permanecen protegidas por RPC + PostgreSQL.

## Verificación antes de producción

Ejecuta `tests/test.html` en staging y todos los scripts bajo `database/tests/`. No promociones una versión con fallos de seguridad, autorización, integridad o SNAKE.

## Recuperación de contraseña en producción

La recuperación usa `request_password_reset()` y entrega el enlace por correo mediante `pg_net` + Resend. Guarda la API key, el remitente y la URL pública en Supabase Vault. Configuración: `database/setup_password_reset_email.sql`. No pongas secretos ni correos reales en el repositorio.
