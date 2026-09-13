const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function fail(message, field) {
  const error = new Error(message);
  error.code = 'VALIDATION_ERROR';
  error.field = field;
  throw error;
}

export function validateEmail(value) {
  const email = String(value ?? '').trim().toLowerCase();
  if (!email) fail('El correo electrónico es obligatorio.', 'email');
  if (email.length > 254 || !EMAIL_RE.test(email)) fail('Introduce un correo electrónico válido.', 'email');
  return email;
}

export function validatePassword(value, { label = 'La contraseña', min = 8, max = 128 } = {}) {
  const password = String(value ?? '');
  if (password.length < min) fail(`${label} debe tener al menos ${min} caracteres.`, 'password');
  if (password.length > max) fail(`${label} no puede superar ${max} caracteres.`, 'password');
  return password;
}

export function validateName(value) {
  const name = String(value ?? '').trim();
  if (name.length < 2) fail('El nombre debe tener al menos 2 caracteres.', 'display_name');
  if (name.length > 80) fail('El nombre no puede superar 80 caracteres.', 'display_name');
  return name;
}

export function validateScore(value, { min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  const score = Number(value);
  if (!Number.isSafeInteger(score) || score < min || score > max) {
    fail(`La puntuación debe estar entre ${min} y ${max}.`, 'score');
  }
  return score;
}

export function validateSlug(value) {
  const slug = String(value ?? '').trim().toLowerCase();
  if (!slug || slug.length > 80 || !SLUG_RE.test(slug)) fail('El identificador del juego no es válido.', 'slug');
  return slug;
}

export function assertPasswordsMatch(password, confirmation) {
  if (String(password) !== String(confirmation)) fail('Las contraseñas no coinciden.', 'confirm_password');
}
