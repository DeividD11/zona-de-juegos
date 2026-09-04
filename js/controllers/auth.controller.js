import { bindAuth } from '../views/auth.view.js';
import { login, register, validate } from '../models/auth.model.js';
import { $, setBusy, setMessage } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { ROUTES } from '../core/constants.js';

function validatePassword(password) {
  if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.');
  if (password.length > 128) throw new Error('La contraseña no puede superar 128 caracteres.');
}

export async function initLogin() {
  if (await validate()) { location.href = ROUTES.dashboard; return; }
  bindAuth('#loginForm', async data => {
    const button = $('#loginSubmit');
    const message = $('#formMessage');
    setMessage(message, '');
    setBusy(button, true, 'Entrando…');
    try {
      await login(String(data.get('email')).trim(), String(data.get('password')));
      location.href = ROUTES.dashboard;
    } catch (error) {
      handleError(error, { target: message, fallback: 'No se pudo iniciar sesión.' });
      setBusy(button, false);
    }
  });
}

export async function initRegister() {
  if (await validate()) { location.href = ROUTES.dashboard; return; }
  bindAuth('#registerForm', async data => {
    const button = $('#registerSubmit');
    const message = $('#formMessage');
    setMessage(message, '');
    setBusy(button, true, 'Creando cuenta…');
    try {
      const password = String(data.get('password'));
      const confirm = String(data.get('confirm_password'));
      validatePassword(password);
      if (password !== confirm) throw new Error('Las contraseñas no coinciden.');
      await register(String(data.get('display_name')).trim(), String(data.get('email')).trim(), password);
      location.href = ROUTES.dashboard;
    } catch (error) {
      handleError(error, { target: message, fallback: 'No se pudo crear la cuenta.' });
      setBusy(button, false);
    }
  });
}
