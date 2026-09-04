import { rpc } from '../core/api.js';
import { getToken } from '../core/session.js';

export async function getAdminData() {
  return rpc('admin_get_data', { p_session_token: getToken() });
}

export async function setUserRole(userId, role) {
  return rpc('admin_set_user_role', {
    p_session_token: getToken(), p_user_id: userId, p_role: role
  });
}

export async function setGameActive(gameId, isActive) {
  return rpc('admin_set_game_active', {
    p_session_token: getToken(), p_game_id: gameId, p_is_active: isActive
  });
}
