import { api } from '../core/api.js';
import { getToken } from '../core/session.js';

export function list() {
  return api.games.list(getToken());
}

export function catalog() {
  return api.games.catalog(getToken());
}
