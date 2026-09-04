import { ROUTES } from './constants.js';
import { can, ACTIONS } from './authorization.js';
import { validate, getToken } from './session.js';

export async function requireAuth() {
  if (!getToken()) { location.href = ROUTES.login; return null; }
  const user = await validate();
  if (!user) { location.href = ROUTES.login; return null; }
  return user;
}

export async function requirePermission(action, resource = null) {
  const user = await requireAuth();
  if (!user) return null;
  if (!can(user, action, resource)) {
    location.href = ROUTES.dashboard;
    return null;
  }
  return user;
}

export async function requireAdmin() {
  return requirePermission(ACTIONS.MANAGE_USERS);
}
