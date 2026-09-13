export function normalizeUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    display_name: user.display_name ?? user.name ?? '',
    email: user.email ?? '',
    role: user.role ?? 'user',
    is_active: user.is_active ?? true,
    created_at: user.created_at ?? null
  };
}

export function createSessionService({ apiClient, storage }) {
  function getToken() {
    return storage.getItem('zona_session_token');
  }

  function clearSession() {
    storage.removeItem('zona_session_token');
    storage.removeItem('zona_user');
    apiClient.cache?.clear?.();
  }

  function storeAuth(auth) {
    if (!auth?.session_token || !auth?.user) throw new Error('La respuesta de autenticación no es válida.');
    const user = normalizeUser(auth.user);
    storage.setItem('zona_session_token', auth.session_token);
    storage.setItem('zona_user', JSON.stringify(user));
    return user;
  }

  async function register(displayName, email, password) {
    return storeAuth(await apiClient.auth.register(displayName, email, password));
  }

  async function login(email, password) {
    return storeAuth(await apiClient.auth.login(email, password));
  }

  async function validate() {
    const token = getToken();
    if (!token) return null;
    // NETWORK_ERROR nunca invalida una sesión local. Solo una respuesta nula
    // del endpoint de sesión confirma que el token dejó de ser válido.
    const user = normalizeUser(await apiClient.sessions.validate(token));
    if (!user) {
      clearSession();
      return null;
    }
    storage.setItem('zona_user', JSON.stringify(user));
    return user;
  }

  async function logout() {
    const token = getToken();
    clearSession();
    if (!token) return true;
    try { await apiClient.sessions.logout(token); } catch { /* revocación local ya realizada */ }
    return true;
  }

  function revokeOtherSessions() {
    const token = getToken();
    return token ? apiClient.sessions.revokeOther(token) : null;
  }

  function changePassword(currentPassword, newPassword) {
    const token = getToken();
    if (!token) throw new Error('Sesión expirada. Inicia sesión nuevamente.');
    return apiClient.sessions.changePassword(token, currentPassword, newPassword);
  }

  return Object.freeze({
    getToken, clearSession, storeAuth, register, login, validate, logout,
    revokeOtherSessions, changePassword,
    requestPasswordReset: email => apiClient.auth.requestPasswordReset(email),
    resetPasswordWithToken: (token, password) => apiClient.auth.resetPassword(token, password)
  });
}
