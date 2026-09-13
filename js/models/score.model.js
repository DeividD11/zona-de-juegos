import { api } from '../core/api.js';
import { getToken } from '../core/session.js';

export function listMine() {
  return api.scores.listMine(getToken());
}
