import { api } from '../core/api.js';
import { getToken } from '../core/session.js';

export function usersPage(page, limit) {
  return api.admin.usersPage(getToken(), page, limit);
}

export function games() {
  return api.admin.games(getToken());
}

export function scoresPage(page, limit) {
  return api.admin.scoresPage(getToken(), page, limit);
}

export function sessionsPage(page, limit) {
  return api.admin.sessionsPage(getToken(), page, limit);
}

export function auditPage(page, limit) {
  return api.admin.auditPage(getToken(), page, limit);
}

export function setUserRole(userId, role) {
  return api.admin.setUserRole(getToken(), userId, role);
}

export function setGameActive(gameId, isActive) {
  return api.admin.setGameActive(getToken(), gameId, isActive);
}
