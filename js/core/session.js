import { STORAGE_KEY, USER_STORAGE_KEY } from './constants.js';
import { api } from './api.js';
import { createSessionService as createService, normalizeUser } from './session.service.js';

const storage = {
  getItem: key => sessionStorage.getItem(key),
  setItem: (key, value) => sessionStorage.setItem(key, value),
  removeItem: key => sessionStorage.removeItem(key)
};

const service = createService({
  apiClient: api,
  storage: {
    ...storage,
    getItem: key => storage.getItem(key === 'zona_session_token' ? STORAGE_KEY : USER_STORAGE_KEY),
    setItem: (key, value) => storage.setItem(key === 'zona_session_token' ? STORAGE_KEY : USER_STORAGE_KEY, value),
    removeItem: key => storage.removeItem(key === 'zona_session_token' ? STORAGE_KEY : USER_STORAGE_KEY)
  }
});

export { createService as createSessionService, normalizeUser };
export const getToken = service.getToken;
export const clearSession = service.clearSession;
export const storeAuth = service.storeAuth;
export const register = service.register;
export const login = service.login;
export const logout = service.logout;
export const validate = service.validate;
export const revokeOtherSessions = service.revokeOtherSessions;
export const changePassword = service.changePassword;
export const requestPasswordReset = service.requestPasswordReset;
export const resetPasswordWithToken = service.resetPasswordWithToken;
