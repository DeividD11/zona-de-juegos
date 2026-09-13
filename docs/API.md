# API única

`js/core/api.js` es la única capa del navegador que construye llamadas RPC de Supabase.

Dominios públicos:

```text
api.auth
  register()
  login()
  requestPasswordReset()
  resetPassword()

api.sessions
  validate()
  logout()
  revokeOther()
  changePassword()

api.games
  list()
  catalog()

api.gameSessions
  start()

api.scores
  listMine()
  save()

api.statistics
  mine()

api.admin
  usersPage()
  games()
  scoresPage()
  sessionsPage()
  auditPage()
  setUserRole()
  setGameActive()
```

Los controladores aplican validaciones de UX y reglas del juego antes de llamar a la API. No existen modelos que repitan las mismas llamadas RPC.
