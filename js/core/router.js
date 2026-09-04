import { ROUTES } from './constants.js';

export function go(route) {
  location.href = route;
}

export function home() { go(ROUTES.dashboard); }
