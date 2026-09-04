import { rpc } from '../core/api.js';
import { getToken } from '../core/session.js';

export async function startGame(gameSlug) {
  return rpc('start_game', { p_session_token: getToken(), p_game_slug: gameSlug });
}

export async function finishGame(gameSessionId, score) {
  return rpc('finish_game', {
    p_session_token: getToken(),
    p_game_session_id: gameSessionId,
    p_score: score
  });
}

export async function getMyScores() {
  return rpc('my_scores', { p_session_token: getToken() });
}
