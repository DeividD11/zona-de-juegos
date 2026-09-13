# Modelo conceptual de datos

```text
app_users
    │
    ├── sessions
    ├── game_scores ───── games
    └── game_sessions ─── games
                │
                └── game_scores

admin_audit_log ─── app_users (admin)

game_statistics ─── app_users + games
leaderboard_*  ─── game_scores + app_users + games
```

## Responsabilidades

- `app_users`: identidad, credenciales derivadas y rol de aplicación.
- `sessions`: sesiones propias, expiración y revocación.
- `games`: catálogo, publicación y `current_version`.
- `game_sessions`: una partida concreta, versión, tiempos y estado.
- `game_scores`: resultados individuales e históricos.
- `game_statistics`: agregados por usuario/juego para lecturas rápidas.
- `admin_audit_log`: trazabilidad de operaciones privilegiadas.
- `leaderboard_*`: vistas derivadas para ranking global, semanal y mensual.

La aplicación accede mediante RPC. RLS y las comprobaciones internas de las RPC son capas defensivas independientes.
