import { rpc } from '../core/api.js';
import { getToken } from '../core/session.js';

export async function listGames() {
  return rpc('list_games', { p_session_token: getToken() });
}
