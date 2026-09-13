import { SUPABASE_CONFIG } from '../config/supabase.config.js';
import { AppError } from './errors.js';

async function parseError(response) {
  let body = null;
  try { body = await response.json(); } catch { /* respuesta de error sin JSON */ }
  const message = body?.message || body?.hint || body?.details || `Error HTTP ${response.status}`;
  return new AppError(message, {
    code: `HTTP_${response.status}`,
    retryable: response.status >= 500
  });
}

const cache = new Map();
const inflight = new Map();

function cacheKey(scope, args) {
  return `${scope}:${JSON.stringify(args ?? null)}`;
}

async function rpc(functionName, payload = {}) {
  let response;
  try {
    response = await fetch(`${SUPABASE_CONFIG.url}/rest/v1/rpc/${functionName}`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_CONFIG.publishableKey,
        Authorization: `Bearer ${SUPABASE_CONFIG.publishableKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify(payload)
    });
  } catch (error) {
    throw new AppError('El servidor no está disponible. Revisa tu conexión e inténtalo de nuevo.', {
      code: 'NETWORK_ERROR',
      retryable: true,
      cause: error
    });
  }

  if (!response.ok) throw await parseError(response);
  if (response.status === 204) return null;

  try {
    return await response.json();
  } catch (error) {
    throw new AppError('El servidor devolvió una respuesta no válida.', {
      code: 'INVALID_RESPONSE',
      retryable: true,
      cause: error
    });
  }
}

/**
 * Contrato único de acceso a datos. Los modelos no construyen RPC a mano;
 * consumen esta API tipada por dominio. Las respuestas de perfil/juegos son DTOs
 * mínimos; nunca se exponen password_hash ni filas completas de tablas.
 */
function cached(scope, args, loader, ttlMs = 15000) {
  const key = cacheKey(scope, args);
  const now = Date.now();
  const current = cache.get(key);
  if (current && current.expiresAt > now) return Promise.resolve(current.value);

  if (inflight.has(key)) return inflight.get(key);

  const promise = Promise.resolve().then(loader).then(value => {
    cache.set(key, { value, expiresAt: Date.now() + ttlMs });
    return value;
  }).finally(() => inflight.delete(key));

  inflight.set(key, promise);
  return promise;
}

function invalidate(scope, args = undefined) {
  if (args === undefined) {
    for (const key of cache.keys()) if (key.startsWith(`${scope}:`)) cache.delete(key);
    return;
  }
  cache.delete(cacheKey(scope, args));
}

function clearCache() {
  cache.clear();
}

export const api = Object.freeze({
  cache: Object.freeze({ invalidate, clear: clearCache }),
  auth: Object.freeze({
    register: (displayName, email, password) => rpc('register_user', {
      p_display_name: displayName,
      p_email: email,
      p_password: password
    }),
    login: (email, password) => rpc('login_user', {
      p_email: email,
      p_password: password
    }),
    requestPasswordReset: email => rpc('request_password_reset', {
      p_email: email
    }),
    resetPassword: (token, newPassword) => rpc('reset_password_with_token', {
      p_token: token,
      p_new_password: newPassword
    })
  }),

  sessions: Object.freeze({
    validate: sessionToken => rpc('get_session', {
      p_session_token: sessionToken
    }),
    logout: sessionToken => rpc('logout_user', {
      p_session_token: sessionToken
    }),
    revokeOther: sessionToken => rpc('revoke_other_sessions', {
      p_session_token: sessionToken
    }),
    changePassword: (sessionToken, currentPassword, newPassword) => rpc('change_password', {
      p_session_token: sessionToken,
      p_current_password: currentPassword,
      p_new_password: newPassword
    })
  }),

  games: Object.freeze({
    list: sessionToken => cached('games.list', [sessionToken], () => rpc('list_games', {
      p_session_token: sessionToken
    })),
    catalog: sessionToken => cached('games.catalog', [sessionToken], () => rpc('list_game_catalog', {
      p_session_token: sessionToken
    }), 10000)
  }),

  gameSessions: Object.freeze({
    start: (sessionToken, gameSlug, gameVersion) => rpc('start_game', {
      p_session_token: sessionToken,
      p_game_slug: gameSlug,
      p_game_version: gameVersion
    })
  }),

  scores: Object.freeze({
    listMine: sessionToken => cached('scores.mine', [sessionToken], () => rpc('my_scores', {
      p_session_token: sessionToken
    }), 10000),
    save: async (sessionToken, gameSessionId, score, metadata = {}) => {
      const result = await rpc('finish_game', {
        p_session_token: sessionToken,
        p_game_session_id: gameSessionId,
        p_score: score,
        p_metadata: metadata
      });
      invalidate('scores.mine', [sessionToken]);
      invalidate('games.catalog', [sessionToken]);
      invalidate('statistics.mine', [sessionToken]);
      return result;
    }
  }),
  statistics: Object.freeze({
    mine: sessionToken => cached('statistics.mine', [sessionToken], () => rpc('my_game_statistics', {
      p_session_token: sessionToken
    }), 10000)
  }),

  admin: Object.freeze({
    usersPage: (sessionToken, page = 1, limit = 20) => rpc('admin_list_users_page', {
      p_session_token: sessionToken, p_page: page, p_limit: limit
    }),
    games: sessionToken => rpc('admin_list_games', {
      p_session_token: sessionToken
    }),
    scoresPage: (sessionToken, page = 1, limit = 20) => rpc('admin_list_scores_page', {
      p_session_token: sessionToken, p_page: page, p_limit: limit
    }),
    sessionsPage: (sessionToken, page = 1, limit = 20) => rpc('admin_list_sessions_page', {
      p_session_token: sessionToken, p_page: page, p_limit: limit
    }),
    auditPage: (sessionToken, page = 1, limit = 20) => rpc('admin_list_audit_page', {
      p_session_token: sessionToken, p_page: page, p_limit: limit
    }),
    usersCursor: (sessionToken, cursor = null, limit = 20) => rpc('admin_list_users_cursor', {
      p_session_token: sessionToken, p_cursor: cursor, p_limit: limit
    }),
    scoresCursor: (sessionToken, cursor = null, limit = 20) => rpc('admin_list_scores_cursor', {
      p_session_token: sessionToken, p_cursor: cursor, p_limit: limit
    }),
    sessionsCursor: (sessionToken, cursor = null, limit = 20) => rpc('admin_list_sessions_cursor', {
      p_session_token: sessionToken, p_cursor: cursor, p_limit: limit
    }),
    auditCursor: (sessionToken, cursor = null, limit = 20) => rpc('admin_list_audit_cursor', {
      p_session_token: sessionToken, p_cursor: cursor, p_limit: limit
    }),
    setUserRole: (sessionToken, userId, role) => rpc('admin_set_user_role', {
      p_session_token: sessionToken,
      p_user_id: userId,
      p_role: role
    }),
    setGameActive: (sessionToken, gameId, isActive) => rpc('admin_set_game_active', {
      p_session_token: sessionToken,
      p_game_id: gameId,
      p_is_active: isActive
    })
  })
});

