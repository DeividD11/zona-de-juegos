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

## Contrato común y registro de juegos

`js/games/registry.js` es el único punto de descubrimiento de juegos y usa `dynamic import` para cargar cada motor bajo demanda.

El contrato común está definido en `js/games/game.contract.js` y exige:

```text
init()
start()
pause()
resume()
restart()
destroy()
getScore()
getState()
```

Para incorporar un juego nuevo no se modifica el Dashboard ni el controlador central: se crea su módulo y se agrega una entrada a `GameRegistry`.

## Tecnologías

- HTML5
- CSS3
- JavaScript ES Modules
- Supabase REST API / PostgreSQL
- PostgreSQL `pgcrypto`

No se utilizan React, Vue, Angular, jQuery, PHP, Python, Node.js como backend de la aplicación ni Supabase Auth.

## Arquitectura MVC

- **Model:** `js/core/api.js` para datos remotos y los modelos propios de cada juego para su estado/reglas. No existen wrappers de modelos duplicando RPC.
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
│   │   ├── app.config.js
│   │   └── supabase.config.js
│   ├── core/
│   │   ├── api.js
│   │   ├── authorization.js
│   │   ├── constants.js
│   │   ├── errors.js
│   │   ├── guards.js
│   │   ├── session.js
│   │   ├── session.service.js
│   │   ├── validators.js
│   │   └── …
│   ├── views/
│   ├── controllers/
│   └── games/
│       ├── game.contract.js
│       ├── registry.js
│       └── <slug>/
├── database/
├── docs/
└── tests/
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


## Rendimiento y escalabilidad

- `api.js` mantiene caché corta en memoria y deduplica solicitudes simultáneas seguras (`games.list`, `games.catalog`, `scores.mine`).
- El Dashboard mantiene la carga paralela de catálogo y puntuaciones.
- La pantalla de juego usa el catálogo, que ya incluye `best_score`, evitando una segunda consulta de puntuaciones para iniciar SNAKE.
- El registro de juegos usa importación dinámica: el código de SNAKE no se descarga mientras el usuario está en Login o Dashboard.
- SNAKE amortiza el fondo y la cuadrícula del canvas; durante cada tick solo se redibujan los elementos dinámicos. Los cambios de tamaño se agrupan mediante `requestAnimationFrame`.
- La tabla `game_scores` conserva los resultados históricos; `game_statistics` separa agregados por usuario/juego; vistas de leaderboard global/semanal/mensual dejan preparado el ranking sin acoplarlo a la vista.

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

## Contrato común de juegos

Todo controlador registrado en `js/games/registry.js` debe implementar el contrato conceptual:

```text
init()
start()
pause()
resume()
restart()
destroy()
getScore()
getState()
```

El controlador central solo resuelve `slug → GameController` mediante `GameRegistry`. No conoce reglas, tablero, controles ni lógica interna de un juego concreto.

La separación de responsabilidades es:

```text
games
  → catálogo y metadatos de juegos
game_sessions
  → una partida concreta: inicio, estado y finalización
game_scores
  → resultado persistido e historial por usuario
```

Para añadir un juego nuevo:

1. Crear `js/games/<slug>/<slug>.model.js`.
2. Crear `js/games/<slug>/<slug>.view.js`.
3. Crear `js/games/<slug>/<slug>.controller.js` respetando el contrato común.
4. Registrar el controlador en `js/games/registry.js`.
5. Insertar o activar su registro en la tabla `games`.

El Dashboard y el controlador central no necesitan conocer la implementación del nuevo juego.

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

## API de datos unificada

`js/core/api.js` es la única capa que conoce los nombres de las RPC de Supabase y expone operaciones agrupadas por dominio:

```js
api.auth.login()
api.auth.register()
api.games.list()
api.gameSessions.start()
api.scores.save()
api.scores.listMine()
api.admin.users()
api.admin.games()
```

Los modelos son adaptadores del dominio y obtienen el token desde `core/session.js`. Así se evita mezclar RPC, persistencia de sesión y lógica de interfaz dentro de los controladores.

## Sesión y logout

`js/core/session.js` es el único responsable de la persistencia, validación y cierre de sesión. Los controladores pueden invocar `logout()`, pero no implementan el cierre contra Supabase por separado.

## Manejo de errores y estados de UI

`js/core/errors.js` unifica errores técnicos, errores de red, servidor no disponible y sesión expirada. Las vistas contemplan estados de carga, éxito, vacío, error, reintento y controles deshabilitados durante operaciones asíncronas.

## Validaciones centralizadas

`js/core/validators.js` concentra las reglas de entrada reutilizables para correo, contraseña, nombre, puntuación e identificador de juego. Los controladores validan datos antes de enviarlos y los modelos de dominio vuelven a validar los valores críticos de partida.

## Ciclo de vida y recursos de los juegos

Cada juego es propietario de sus listeners y timers. El ciclo recomendado es:

```text
mount()
  → bindEvents()
  → start()/pause()/resume()/restart()
  → unbindEvents()
  → destroy()
```

`destroy()` debe cancelar todos los `setInterval`, `setTimeout` y `requestAnimationFrame` creados por el juego y retirar sus listeners. Esto permite cambiar de pantalla o reemplazar una instancia sin fugas ni eventos duplicados.

SNAKE mantiene una cola de direcciones para procesar entradas rápidas y usa estados explícitos `READY`, `PLAYING`, `PAUSED`, `GAME_OVER` y `DESTROYED`. La dirección pendiente se toma como referencia al validar la siguiente entrada, evitando inversiones inválidas causadas por pulsaciones consecutivas.


## Game Over, guardado y trazabilidad de SNAKE

Al terminar una partida, la interfaz muestra:

```text
GAME OVER

Puntuación: 120
Mejor puntuación: 240

Guardando puntuación...
✓ Puntuación guardada
```

Si el servidor rechaza o no puede guardar el resultado, se muestra un estado visible de error sin ocultar el resultado local.

El canvas se dimensiona usando el ancho real del contenedor, el viewport y `devicePixelRatio`, evitando tamaños rígidos para pantallas pequeñas o densidades altas.

Cada partida de SNAKE puede conservar metadatos de trazabilidad. `game_sessions.started_at` y `finished_at` son la fuente de verdad del servidor; `duration`, `score` y `game_version` quedan registrados en `game_sessions.metadata`. El cliente puede enviar metadatos opcionales, pero el servidor sobrescribe `start_time`, `end_time`, `duration`, `score` y `game_version` con valores calculados o controlados por la partida.

La versión actual de SNAKE se declara en `SNAKE_CONFIG.version`. Esto permite comparar resultados históricos y detectar cambios de reglas.

## Migración de metadatos

Para una base de datos existente creada con una versión anterior del proyecto, ejecutar:

`database/migration_002_game_metadata.sql`

Si se instala desde cero, `database/schema.sql` ya contiene las columnas `game_version` y `metadata` en `game_sessions`.


## API de datos

`js/core/api.js` es la única capa que construye y ejecuta las llamadas RPC. Se organiza por dominio:

```text
api.auth.*
api.games.*
api.gameSessions.*
api.scores.*
api.admin.*
```

Los modelos de dominio son adaptadores pequeños; no contienen URLs RPC ni lógica de interfaz. La persistencia y el logout permanecen centralizados en `js/core/session.js`.


### Reparación de RPC de partidas

Si Supabase muestra `function public.start_game(text, text) does not exist`, ejecuta `database/migration_003_repair_game_rpcs.sql` después de `schema.sql` (o `database/fix_game_rpcs.sql` desde una sesión psql). Esta migración es idempotente y recrea las RPC actuales de inicio y finalización. No uses la migración 002 anterior de versiones que elimina RPC sin reinstalarlas.

## Integridad, índices, paginación, auditoría y versiones

La base de datos aplica `NOT NULL`, `CHECK`, `UNIQUE` y `FOREIGN KEY` donde son reglas estructurales del dominio. Las partidas validan la coherencia entre estado, puntuación y fechas; las sesiones y tokens no pueden expirar antes de crearse.

Los índices se mantienen ligados a consultas reales: relación por usuario, relación por juego, fechas de creación, expiración de sesiones y auditoría. La partida activa tiene un índice único parcial por usuario/juego para impedir duplicados concurrentes.

El panel administrativo usa paginación con `page` y `limit` para usuarios, puntuaciones, sesiones y auditoría; nunca descarga colecciones administrativas ilimitadas.

`admin_audit_log` registra cambios administrativos exitosos con administrador, acción, objetivo, fecha, resultado y metadatos.

Cada juego tiene `games.current_version`. Al iniciar una partida, la versión publicada del juego se copia a `game_sessions.game_version`, de modo que las puntuaciones históricas permanecen trazables aunque cambien las reglas del juego.

Para instalaciones existentes, ejecutar `database/migration_004_integrity_admin.sql` después de las migraciones anteriores. Esta migración también repara las RPC de partidas y publica la versión actual de SNAKE. Para una instalación nueva, `database/schema.sql` contiene estas reglas y funciones.


## Seguridad de RPC y DTOs
- Las tablas sensibles no tienen acceso directo desde `anon`/`authenticated`.
- Las RPC con privilegios administrativos verifican el token de sesión y rol mediante `_require_admin()` dentro de PostgreSQL.
- `get_session()` y `list_games()` devuelven DTOs mínimos, nunca filas completas.
- La migración `database/migration_006_security_dto.sql` endurece permisos y actualiza DTOs.


### Catálogo y experiencia de juego (versión actual)
El dashboard usa `list_game_catalog` para mostrar cada juego con estado `🟢 Disponible`, `🟡 Próximamente` o `🔴 Desactivado`, además de versión y mejor puntuación. Ejecuta `database/migration_007_game_catalog.sql` en instalaciones existentes.

### Carga de juegos
El controlador de juegos usa `js/core/api.js` y el registro dinámico; los modelos obsoletos fueron eliminados. El juego mantiene un estado de error con botón de reintento para no dejar la pantalla congelada en “Cargando juego…”.
## Registro de juegos y convenciones

Los juegos siguen una convención de nombres por capa: JavaScript usa `camelCase` para variables y funciones, clases con `PascalCase`, SQL usa `snake_case` y los slugs públicos son `kebab-case` cuando lo requieren varias palabras.

`js/games/registry.js` es el único catálogo de carga de juegos. Cada entrada usa importación dinámica, por lo que Login y Registro no descargan motores de juegos. Para añadir un juego nuevo se crea su módulo bajo `js/games/<slug>/`, se implementa el contrato común y se registra una sola entrada en `GameRegistry`. El controlador del Dashboard no necesita cambios.

Los módulos que todavía no están publicados pueden existir como `upcoming` e `is_active = false` en PostgreSQL. Esto permite preparar catálogo, versionado y permisos sin habilitar una implementación incompleta.

## Decisiones de mantenimiento

La aplicación evita comentarios que solo repitan el código. Se documentan únicamente decisiones que afectan seguridad, despliegue o reglas del dominio, como `SECURITY DEFINER`, límites de sesión, cálculo de puntuación y carga dinámica de juegos.

## Headers de despliegue

`_headers` define los controles para hosts estáticos compatibles (por ejemplo, Netlify) y `vercel.json` define los mismos controles para Vercel. La CSP bloquea scripts inline y limita las conexiones de datos al origen de Supabase utilizado por la aplicación. HSTS debe servirse únicamente bajo HTTPS; en producción se espera despliegue seguro mediante el proveedor de hosting.

## Migración 009

Para instalaciones existentes, ejecutar `database/migration_009_game_registry.sql`. Esta migración registra TETRIS, PONG, MEMORY y MINESWEEPER como juegos próximos sin modificar el núcleo de control.

## Seguridad de transporte y despliegue

La autenticación y las sesiones no se ejecutan sobre HTTP fuera del entorno local. `js/core/transport-security.js` bloquea el arranque en `staging` y `production` y redirige a HTTPS. El entorno se determina en `js/config/app.config.js`.

La estrategia de despliegue está documentada en `deployment.md` con separación `Development`, `Staging` y `Production`.

En despliegue se aplican CSP estricta, HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` y protección contra framing mediante `_headers` o `vercel.json`. No se usan scripts o estilos inline.

## Modelo de datos

El diagrama conceptual y la responsabilidad de cada entidad están documentados en `database/DATABASE.md`.

```text
app_users
    │
    ├── sessions
    ├── game_scores ───── games
    └── game_sessions ─── games
                │
                └── game_scores
```

`game_statistics` y las vistas `leaderboard_*` son estructuras derivadas y no sustituyen el historial detallado de `game_scores`.

## Incorporar un juego nuevo

El cambio ideal está aislado al juego y su metadata. Sigue este orden:

1. Crear `js/games/<slug>/`.
2. Crear el `model` con las reglas y estado del juego.
3. Crear el `view` con el DOM accesible y controles.
4. Crear el `controller` respetando `init()`, `start()`, `pause()`, `resume()`, `restart()`, `destroy()`, `getScore()` y `getState()`.
5. Registrar el juego en `js/games/registry.js` mediante importación dinámica.
6. Registrar nombre, slug, descripción, icono, estado y `current_version` en `games` con SQL.
7. Mantener el `game_version` de cada `game_session` para trazabilidad del score.
8. Ejecutar la suite local y los checks SQL de staging antes de publicar.

No debe ser necesario modificar `dashboard.controller.js`, `auth.controller.js` ni otros núcleos para añadir un juego concreto.


## Documentación adicional

- `database/RPC_MATRIX.md`: matriz de permisos y contrato de RPC.
- `database/bootstrap_admin.sql`: bootstrap manual y de una sola ejecución.
- `docs/ADDING_A_GAME.md`: procedimiento para incorporar juegos sin tocar el núcleo.
- `database/schema.sql`: instalación completa desde cero; las `migration_*.sql` solo actualizan instalaciones antiguas.


## V22 — mantenimiento y lifecycle

La versión v22 elimina los modelos de datos obsoletos sin consumidores. El acceso a Supabase se concentra en `js/core/api.js`, los controladores de página se montan mediante `js/core/lifecycle.js` y el controlador de juego expone `destroyGame()` para liberar el juego activo. `database/schema.sql` contiene una única definición final de cada RPC administrativa; las migraciones quedan reservadas para instalaciones existentes.

## V23: seguridad y escala

La recuperación de contraseña ya dispone de un canal real de entrega mediante `pg_net` + Resend, con secretos protegidos por Supabase Vault. La auditoría administrativa registra actor, acción, objetivo, fecha, resultado y metadata mínima. Para crecimiento, existen RPC administrativas con paginación por cursor además de las RPC OFFSET de compatibilidad.

## Corrección de migración 012

Si ya intentaste ejecutar `migration_012_security_audit_recovery.sql` y PostgreSQL respondió con el error `42601` cerca de `not`, ejecuta `database/migration_013_fix_migration_012_syntax.sql` después de corregir/reintentar la migración 012. La causa era la declaración inválida `p_target_id uuid not null` dentro de la firma de una función. La versión corregida valida `p_target_id` dentro del cuerpo de la función.
