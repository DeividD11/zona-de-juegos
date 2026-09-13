# Incorporar un juego

1. Crear `js/games/<slug>/` con `model.js`, `view.js` y `controller.js`.
2. Implementar el contrato común: `init`, `start`, `pause`, `resume`, `restart`, `destroy`, `getScore`, `getState` y lifecycle `mount/bindEvents/unbindEvents`.
3. Registrar el loader en `js/games/registry.js`; no modificar `dashboard.controller.js`.
4. Registrar metadata en PostgreSQL (`slug`, `current_version`, `score_ceiling`, `release_status`, `is_active`).
5. Definir el modelo de score y las reglas de validación en PostgreSQL.
6. Crear/actualizar RPCs únicamente si el juego necesita reglas adicionales; mantener DTOs mínimos y autorización interna.
7. Probar motor, lifecycle, resize, puntuación y autorización en staging.
8. Activar el juego desde una operación administrativa auditada.

El núcleo de dashboard, sesión y API no necesita conocer la implementación concreta del juego.
