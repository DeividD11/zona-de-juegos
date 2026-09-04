import { SUPABASE_CONFIG } from '../config/supabase.config.js';
import { AppError } from './errors.js';

async function parseError(response) {
  let body = null;
  try { body = await response.json(); } catch { /* ignore invalid error body */ }
  const message = body?.message || body?.hint || body?.details || `Error HTTP ${response.status}`;
  return new AppError(message, { code: `HTTP_${response.status}`, retryable: response.status >= 500 });
}

export async function rpc(functionName, payload = {}) {
  let response;
  try {
    response = await fetch(`${SUPABASE_CONFIG.url}/rest/v1/rpc/${functionName}`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_CONFIG.publishableKey,
        Authorization: `Bearer ${SUPABASE_CONFIG.publishableKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify(payload)
    });
  } catch (error) {
    throw new AppError('El servidor no está disponible. Revisa tu conexión e inténtalo de nuevo.', {
      code: 'NETWORK_ERROR', retryable: true, cause: error
    });
  }

  if (!response.ok) throw await parseError(response);
  if (response.status === 204) return null;

  try {
    return await response.json();
  } catch (error) {
    throw new AppError('El servidor devolvió una respuesta no válida.', {
      code: 'INVALID_RESPONSE', retryable: true, cause: error
    });
  }
}
