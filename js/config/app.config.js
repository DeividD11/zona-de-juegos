const hostname = window.location.hostname.toLowerCase();

export const APP_ENV = window.__APP_ENV__ || (
  hostname === 'localhost' || hostname === '127.0.0.1'
    ? 'development'
    : hostname.startsWith('staging.') || hostname.includes('.staging.')
      ? 'staging'
      : 'production'
);

export const ENV_CONFIG = Object.freeze({
  development: Object.freeze({ enforceHttps: false }),
  staging: Object.freeze({ enforceHttps: true }),
  production: Object.freeze({ enforceHttps: true })
});

export const ACTIVE_ENV_CONFIG = ENV_CONFIG[APP_ENV] || ENV_CONFIG.production;
