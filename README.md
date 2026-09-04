# Zona de Juegos

Plataforma web de juegos construida con HTML, CSS y JavaScript puro, usando Supabase como base de datos/API. No utiliza Supabase Auth.

## Funcionalidades

- Registro y login propios contra PostgreSQL/Supabase.
- Registro público siempre crea usuarios con rol `user`; el administrador inicial se configura una sola vez mediante `database/bootstrap_admin.sql`.
- Contraseñas hasheadas en PostgreSQL mediante `pgcrypto`.
- Sesiones propias con token aleatorio y hash del token almacenado en la base de datos.
- Dashboard con catálogo de juegos.
- SNAKE completamente funcional con teclado y controles táctiles.
- Partidas verificables con `game_sessions`, validación de duración/puntuación y mejor puntuación por usuario.
- Panel de administración para roles y activación/desactivación de juegos.
- RLS activado, tablas sin acceso directo desde el navegador y RPC con autorización centralizada en PostgreSQL.
- Arquitectura MVC modular y preparada para nuevos juegos.

## Tecnologías

- HTML5
- CSS3
- JavaScript ES Modules
- Supabase REST API / PostgreSQL
- PostgreSQL `pgcrypto`

No se utilizan React, Vue, Angular, jQuery, PHP, Python, Node.js como backend de la aplicación ni Supabase Auth.

## Arquitectura MVC

- **Model:** `js/models/` y `js/core/api.js`. Se ocupa del acceso a la API y de las operaciones de datos.
- **View:** `js/views/` y HTML/CSS. Renderiza formularios, dashboard, panel administrativo y juego.
- **Controller:** `js/controllers/`. Coordina eventos, validaciones, navegación, sesiones y comunicación Model ↔ View.
- **Games:** cada juego mantiene su propio `model`, `view` y `controller` bajo `js/games/<slug>/`.

## Estructura

```text
zona-de-juegos/
├── index.html
├── login.html
├── register.html
├── forgot-password.html
├── reset-password.html
├── dashboard.html
├── admin.html
├── pages/
│   ├── game.html
│   └── profile.html
├── assets/
│   ├── css/
│   │   └── global.css
│   └── images/
├── js/
│   ├── config/
│   │   └── supabase.config.js
│   ├── core/
│   │   ├── api.js
│   │   ├── constants.js
│   │   ├── guards.js
│   │   ├── authorization.js
│   │   ├── errors.js
│   │   ├── router.js
│   │   ├── session.js
│   │   └── utils.js
│   ├── models/
│   │   ├── auth.model.js
│   │   ├── game.model.js
│   │   ├── score.model.js
│   │   ├── session.model.js
│   │   └── user.model.js
│   ├── views/
│   │   ├── auth.view.js
│   │   ├── admin.view.js
│   │   ├── dashboard.view.js
│   │   └── game.view.js
│   ├── controllers/
│   │   ├── auth.controller.js
│   │   ├── admin.controller.js
│   │   ├── dashboard.controller.js
│   │   ├── game.controller.js
│   │   ├── profile.controller.js
│   │   └── recovery.controller.js
│   └── games/
│       ├── registry.js
│       └── snake/
│           ├── snake.model.js
│           ├── snake.view.js
│           └── snake.controller.js
├── database/
│   ├── schema.sql
│   ├── policies.sql
│   ├── seed.sql
│   ├── bootstrap_admin.sql
│   ├── admin_generate_reset_token.sql
│   └── maintenance.sql
└── README.md
```

## Configuración de Supabase

La URL y la publishable key proporcionadas están en:

`js/config/supabase.config.js`

La contraseña real de PostgreSQL no está incluida en el proyecto.

La publishable key no es una clave administrativa. Las operaciones sensibles se protegen mediante RLS y funciones `SECURITY DEFINER` con permisos explícitos.

## Configuración de la base de datos

1. Abrir el SQL Editor del proyecto de Supabase.
2. Ejecutar `database/schema.sql`.
3. Ejecutar `database/policies.sql`.
4. Ejecutar `database/seed.sql`.
5. Verificar que el juego `snake` esté activo.
6. Crear una cuenta normal desde `register.html`.
7. Ejecutar una sola vez `database/bootstrap_admin.sql` en el SQL Editor, reemplazando el correo de ejemplo por el de la cuenta elegida como administrador.

El registro público nunca asigna el rol `admin`. El primer administrador se selecciona manualmente mediante el script de bootstrap, que se bloquea si ya existe cualquier administrador.

## Autenticación propia

No se utiliza `supabase.auth` ni ningún proveedor de autenticación de Supabase.

El flujo es:

```text
Registro/Login
  → función RPC
  → PostgreSQL valida la cuenta
  → pgcrypto comprueba/hash de contraseña
  → PostgreSQL crea sesión
  → navegador recibe token de sesión
  → token se mantiene en sessionStorage
  → cada operación privada vuelve a validar el token en PostgreSQL
```

Las contraseñas nunca se almacenan en texto plano y nunca se guardan en `sessionStorage`/`localStorage`.

El token que mantiene el navegador es un identificador de sesión. La base de datos almacena únicamente el hash SHA-256 del token, además de sus fechas de creación, expiración y revocación.

## Seguridad

- RLS está habilitado en usuarios, juegos, sesiones, puntuaciones, partidas y límites de autenticación.
- `anon` y `authenticated` no reciben acceso directo a las tablas.
- Las operaciones se exponen mediante funciones RPC concretas.
- El rol de administrador se comprueba dentro de PostgreSQL.
- Un usuario no puede asignarse el rol de administrador desde el frontend.
- No se permite eliminar el último administrador activo mediante el RPC de roles.
- Las puntuaciones se asocian al usuario de la sesión validada por PostgreSQL.
- No se expone la contraseña real de PostgreSQL.
- No se incluyen claves administrativas de Supabase.
- Se recomienda desplegar exclusivamente por HTTPS.
- Los tokens del cliente están en `sessionStorage`; esto evita persistencia entre sesiones del navegador, aunque como cualquier secreto accesible por JavaScript requiere una política sólida contra XSS.

## Ejecutar localmente

Al ser un proyecto con ES Modules, sirve la carpeta mediante un servidor estático local. Por ejemplo, con la extensión **Live Server** de VS Code.

No abras las páginas con `file://`, porque el navegador bloqueará parte de los módulos ES.

## Probar el flujo

1. Ejecutar `database/schema.sql`.
2. Ejecutar `database/policies.sql`.
3. Ejecutar `database/seed.sql`.
4. Abrir `register.html` mediante un servidor estático.
5. Crear una cuenta normal.
6. Ejecutar una sola vez `database/bootstrap_admin.sql` con el correo que deba recibir el rol `admin`.
7. Confirmar que aparece como administrador.
8. Entrar al Dashboard.
9. Abrir SNAKE.
10. Iniciar una partida con el botón, las flechas o WASD.
11. Terminar la partida y comprobar que la puntuación aparece en el Dashboard.
12. Entrar a Administración y probar el cambio de roles/estado de juegos.

## Añadir nuevos juegos

1. Crear `js/games/<slug>/<slug>.model.js`.
2. Crear `js/games/<slug>/<slug>.view.js`.
3. Crear `js/games/<slug>/<slug>.controller.js`.
4. Insertar el nuevo juego en `games` desde un SQL seed o mediante una futura pantalla administrativa.
5. Añadir el enrutamiento/inicialización específica en el controlador de juegos.

El resto de la autenticación, sesiones, dashboard y puntuaciones permanece desacoplado del motor de cada juego.

## Despliegue

El proyecto puede desplegarse como sitio estático en un hosting que soporte archivos estáticos y ES Modules. Antes del despliegue:

- Confirmar que `js/config/supabase.config.js` contiene únicamente la URL y publishable key.
- No subir contraseñas de PostgreSQL.
- No subir service role keys ni otras claves administrativas.
- Usar HTTPS.
- Ejecutar los scripts SQL en la base de datos antes de abrir la aplicación.

## Notas de diseño

La arquitectura evita que el navegador haga operaciones directas sobre las tablas sensibles. El navegador llama a funciones RPC específicas; dichas funciones comprueban la sesión y/o el rol antes de realizar la operación.

Esto es especialmente importante porque una arquitectura de autenticación propia en un frontend público no debe intentar implementar un algoritmo de contraseña casero en JavaScript ni confiar solamente en guards visuales.

## Seguridad P0 implementada

- El registro público siempre crea usuarios con rol `user`.
- El primer administrador se configura mediante `database/bootstrap_admin.sql`, ejecutado manualmente una sola vez en Supabase.
- Login y registro incluyen rate limiting respaldado por PostgreSQL.
- SNAKE utiliza `game_sessions` y las puntuaciones solo se aceptan mediante `finish_game()`.
- Las puntuaciones de SNAKE tienen un límite de 3970 puntos y una validación adicional por duración de partida.
- El cambio de roles administrativos está serializado mediante un advisory lock para impedir que dos administradores eliminen concurrentemente el último administrador.
- La RPC pública anterior `save_score()` queda revocada; el frontend usa `start_game()` y `finish_game()`.

### Orden de instalación actualizado

1. Ejecutar `database/schema.sql`.
2. Ejecutar `database/seed.sql`.
3. Crear una cuenta normal desde `register.html`.
4. Abrir `database/bootstrap_admin.sql`, reemplazar el correo de ejemplo por el correo de la cuenta elegida y ejecutarlo manualmente en el SQL Editor de Supabase.
5. Configurar `js/config/supabase.config.js` con la URL y publishable key del proyecto.

> El archivo `database/bootstrap_admin.sql` no debe publicarse como una ruta web. Es un script de administración para el SQL Editor de Supabase.


## Autorización centralizada

El frontend usa `js/core/authorization.js` para decidir navegación y visibilidad de acciones mediante `can(action, resource)`. Esta capa nunca sustituye la seguridad del servidor: PostgreSQL vuelve a validar sesión, rol y propiedad en cada RPC protegida.

Roles:

- `PUBLIC`: acceso únicamente a login/registro.
- `USER`: ver juegos, jugar y consultar/guardar sus propios resultados.
- `ADMIN`: todas las capacidades anteriores y gestión de usuarios, juegos y roles.

## Política de sesiones

- Duración máxima absoluta: 7 días.
- Inactividad máxima: 24 horas.
- Máximo de 5 sesiones activas por usuario.
- Al iniciar sesión con 5 sesiones activas, se revoca la más antigua.
- Desde `pages/profile.html` es posible cerrar todas las demás sesiones.
- Las sesiones expiradas/inactivas se eliminan mediante `cleanup_sessions()`.
- `database/maintenance.sql` contiene el job periódico recomendado con `pg_cron`.


## Seguridad P1 implementada

- Autorización centralizada en frontend con `can(action, resource)` y guards de navegación.
- RPC protegidas mediante helpers internos `_require_session()` y `_require_admin()`.
- Política de sesiones: 7 días de vida absoluta y 24 horas de inactividad.
- Máximo de 5 sesiones activas por usuario.
- Al superar el límite, el login revoca la sesión activa más antigua.
- El perfil permite revocar todas las demás sesiones sin cerrar la actual.
- `cleanup_sessions()` elimina sesiones expiradas, revocadas antiguas o inactivas.
- `database/maintenance.sql` deja preparada la programación periódica con `pg_cron`.



## Gestión de contraseña y recuperación de cuenta

El perfil incluye **Cambiar contraseña** con contraseña actual, nueva contraseña y confirmación. La operación se valida dentro de PostgreSQL; después de actualizarla, se revocan las demás sesiones activas y se mantiene únicamente la sesión desde la que se realizó el cambio.

La recuperación de acceso está separada de la autenticación normal. `request_password_reset()` crea un token aleatorio de un solo uso con expiración de 30 minutos, almacenando solamente su hash. `reset_password_with_token()` valida el token, cambia la contraseña, la marca como usado y revoca todas las sesiones existentes.

Como este proyecto es un frontend estático y deliberadamente no incorpora un backend de correo, `request_password_reset()` no devuelve el token al navegador ni finge haber enviado un correo. Para una instalación sin proveedor de correo se incluye `database/admin_generate_reset_token.sql`, que permite a un operador autorizado generar manualmente un enlace temporal desde el SQL Editor y entregarlo por un canal privado. Para una recuperación automática por correo, ese mismo flujo puede conectarse posteriormente a un proveedor de correo sin cambiar la arquitectura de autenticación.

## GameRegistry

La resolución de juegos está centralizada en `js/games/registry.js`. El controlador general no contiene condicionales por juego: obtiene el `slug`, consulta `GameRegistry[slug]` y entrega al controlador concreto las callbacks comunes de inicio y guardado de puntuación. Para añadir un juego nuevo, crea su módulo MVC y registra su controlador en `GameRegistry`.

## Manejo de errores y estados de UI

`js/core/errors.js` unifica errores técnicos, errores de red, servidor no disponible y sesión expirada. Las vistas contemplan estados de carga, éxito, vacío, error, reintento y controles deshabilitados durante operaciones asíncronas.
