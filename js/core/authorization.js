/**
 * UX authorization matrix. PostgreSQL remains the source of truth for every
 * protected operation; this module only controls navigation and affordances.
 */
export const ROLES = Object.freeze({
  PUBLIC: 'public',
  USER: 'user',
  ADMIN: 'admin'
});

export const ACTIONS = Object.freeze({
  GAMES_READ: 'games.read',
  GAME_PLAY: 'game.play',
  SCORES_CREATE_OWN: 'scores.createOwn',
  SCORES_READ_OWN: 'scores.readOwn',
  USERS_MANAGE: 'users.manage',
  ROLES_MANAGE: 'roles.manage',
  GAMES_MANAGE: 'games.manage',
  SCORES_READ_ALL: 'scores.readAll',
  AUDIT_READ: 'audit.read'
});

const USER_PERMISSIONS = new Set([
  ACTIONS.GAMES_READ,
  ACTIONS.GAME_PLAY,
  ACTIONS.SCORES_CREATE_OWN,
  ACTIONS.SCORES_READ_OWN
]);

const ADMIN_PERMISSIONS = new Set([
  ...USER_PERMISSIONS,
  ACTIONS.USERS_MANAGE,
  ACTIONS.ROLES_MANAGE,
  ACTIONS.GAMES_MANAGE,
  ACTIONS.SCORES_READ_ALL,
  ACTIONS.AUDIT_READ
]);

export function can(user, action, _resource = null) {
  const role = user?.role || ROLES.PUBLIC;
  if (role === ROLES.ADMIN) return ADMIN_PERMISSIONS.has(action);
  if (role === ROLES.USER) return USER_PERMISSIONS.has(action);
  return false;
}
