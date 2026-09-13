import { api } from '../core/api.js';
import { getToken } from '../core/session.js';
import { validateScore, validateSlug } from '../core/validators.js';

export function start(gameSlug, gameVersion = null) {
  return api.gameSessions.start(getToken(), validateSlug(gameSlug), gameVersion);
}

export function finish(gameSessionId, score, { maxScore, metadata = {} } = {}) {
  if (!gameSessionId) throw new Error('La partida no tiene una sesión válida.');
  const safeScore = validateScore(score, Number.isSafeInteger(maxScore) ? { min: 0, max: maxScore } : undefined);
  return api.gameSessions.finish(getToken(), gameSessionId, safeScore, metadata);
}
