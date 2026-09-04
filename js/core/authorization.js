/**
 * Authorization policy for the frontend.
 * This is only a UX/navigation layer. PostgreSQL RPCs remain the final authority.
 */
export const ROLES = Object.freeze({
  PUBLIC: 'public',
  USER: 'user',
  ADMIN: 'admin'
});

export const ACTIONS = Object.freeze({
  VIEW_GAMES: 'view_games',
  PLAY_GAME: 'play_game',
  SAVE_OWN_SCORE: 'save_own_score',
  VIEW_OWN_SCORES: 'view_own_scores',
  MANAGE_USERS: 'manage_users',
  MANAGE_GAMES: 'manage_games',
  MANAGE_ROLES: 'manage_roles'
});

export function can(user, action, resource = null) {
  const role = user?.role || ROLES.PUBLIC;

  if (role === ROLES.ADMIN) return true;

  if (role === ROLES.USER) {
    return [
      ACTIONS.VIEW_GAMES,
      ACTIONS.PLAY_GAME,
      ACTIONS.SAVE_OWN_SCORE,
      ACTIONS.VIEW_OWN_SCORES
    ].includes(action);
  }

  return false;
}
