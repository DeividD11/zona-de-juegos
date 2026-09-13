# Incorporar un juego

El núcleo no conoce las reglas internas de cada juego.

1. Crear `js/games/<slug>/`.
2. Crear el **model** con estado/reglas del juego.
3. Crear la **view** responsable de su DOM/canvas.
4. Crear el **controller** implementando `init()`, `start()`, `pause()`, `resume()`, `restart()`, `destroy()`, `getScore()` y `getState()`.
5. Agregar una entrada en `js/games/registry.js` usando `dynamic import`.
6. Registrar el juego y su metadata en PostgreSQL.
7. Implementar el guardado de score mediante la API común.
8. Añadir pruebas deterministas del motor y del contrato.

No es necesario modificar `dashboard.controller.js` ni crear otra capa de acceso a Supabase.
