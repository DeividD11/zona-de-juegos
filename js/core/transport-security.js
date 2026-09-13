import { ACTIVE_ENV_CONFIG, APP_ENV } from '../config/app.config.js';

export function enforceHttps() {
  if (!ACTIVE_ENV_CONFIG.enforceHttps) return;
  if (window.location.protocol !== 'https:') {
    const target = `https://${window.location.host}${window.location.pathname}${window.location.search}${window.location.hash}`;
    window.location.replace(target);
    throw new Error(`HTTPS requerido en ${APP_ENV}.`);
  }
}
