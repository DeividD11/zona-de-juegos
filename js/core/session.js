import { STORAGE_KEY } from './constants.js';
import { rpc } from './api.js';

export function getToken() {
  return sessionStorage.getItem(STORAGE_KEY);
}

export function clearSession() {
  sessionStorage.removeItem(STORAGE_KEY);
  sessionStorage.removeItem('zona_juegos_user');
}

export function storeAuth(result) {
  sessionStorage.setItem(STORAGE_KEY, result.session_token);
  sessionStorage.setItem('zona_juegos_user', JSON.stringify(result.user));
}

export async function register(displayName, email, password) {
  const result = await rpc('register_user', { p_display_name: displayName, p_email: email, p_password: password });
  storeAuth(result);
  return result.user;
}

export async function login(email, password) {
  const result = await rpc('login_user', { p_email: email, p_password: password });
  storeAuth(result);
  return result.user;
}

export async function logout() {
  const token = getToken();
  try { if (token) await rpc('logout_user', { p_session_token: token }); } finally { clearSession(); }
}

export async function validate() {
  const token = getToken();
  if (!token) return null;
  try {
    const user = await rpc('get_session', { p_session_token: token });
    if (!user) { clearSession(); return null; }
    sessionStorage.setItem('zona_juegos_user', JSON.stringify(user));
    return user;
  } catch {
    clearSession();
    return null;
  }
}

export async function revokeOtherSessions() {
  const token = getToken();
  if (!token) throw new Error('No hay una sesión activa.');
  return rpc('revoke_other_sessions', { p_session_token: token });
}

export async function changePassword(currentPassword, newPassword) {
  const token = getToken();
  if (!token) throw new Error('Sesión expirada.');
  return rpc('change_password', {
    p_session_token: token,
    p_current_password: currentPassword,
    p_new_password: newPassword
  });
}

export async function requestPasswordReset(email) {
  return rpc('request_password_reset', { p_email: email });
}

export async function resetPasswordWithToken(token, newPassword) {
  return rpc('reset_password_with_token', { p_token: token, p_new_password: newPassword });
}
