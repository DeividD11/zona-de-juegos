const NETWORK_MESSAGES = new Map([
  'Failed to fetch',
  'NetworkError when attempting to fetch resource.',
  'Load failed'
].map(message => [message, true]));

export class AppError extends Error {
  constructor(message, { code = 'APP_ERROR', cause = null, retryable = false } = {}) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.cause = cause;
    this.retryable = retryable;
  }
}

export function toAppError(error, fallback = 'Ocurrió un problema. Inténtalo de nuevo.') {
  if (error instanceof AppError) return error;

  const raw = String(error?.message || '').trim();
  const normalized = raw.toLowerCase();

  if (!raw || NETWORK_MESSAGES.has(raw) || normalized.includes('failed to fetch') || normalized.includes('networkerror')) {
    return new AppError('El servidor no está disponible. Revisa tu conexión e inténtalo de nuevo.', {
      code: 'NETWORK_ERROR', retryable: true, cause: error
    });
  }

  if (normalized.includes('sesión no válida') || normalized.includes('sesion no valida') || normalized.includes('sesión expirada') || normalized.includes('sesion expirada')) {
    return new AppError('Sesión expirada. Inicia sesión nuevamente.', {
      code: 'SESSION_EXPIRED', cause: error
    });
  }

  if (/^error http 5\d\d/i.test(raw)) {
    return new AppError('El servidor no está disponible. Inténtalo de nuevo.', {
      code: 'SERVER_ERROR', retryable: true, cause: error
    });
  }

  if (/PGRST|postgrest|relation .* does not exist|column .* does not exist|syntax error|permission denied/i.test(raw)) {
    return new AppError('No se pudo completar la operación en el servidor. Inténtalo de nuevo.', {
      code: 'BACKEND_ERROR', retryable: true, cause: error
    });
  }

  return new AppError(raw || fallback, { cause: error });
}

export function handleError(error, {
  target = null,
  fallback = 'Ocurrió un problema. Inténtalo de nuevo.',
  type = 'error',
  retry = null
} = {}) {
  const appError = toAppError(error, fallback);
  if (appError.code === 'SESSION_EXPIRED') {
    sessionStorage.removeItem('zona_juegos_session');
    sessionStorage.removeItem('zona_juegos_user');
  }

  if (target) {
    target.textContent = appError.message;
    target.className = `message message--${type}`;
    target.hidden = false;
    target.setAttribute('role', 'alert');
    target.setAttribute('aria-live', 'assertive');
    if (retry && appError.retryable) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'button button--small button--ghost message__retry';
      button.textContent = 'Reintentar';
      button.addEventListener('click', retry, { once: true });
      target.append(' ', button);
    }
  }

  console.error(error);
  return appError;
}
