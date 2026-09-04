import { requestPasswordReset, resetPasswordWithToken } from '../models/auth.model.js';
import { $, setBusy, setMessage, getQueryParam } from '../core/utils.js';
import { handleError } from '../core/errors.js';

export function initForgotPassword() {
  $('#forgotPasswordForm')?.addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = $('#forgotPasswordButton');
    const message = $('#formMessage');
    const email = String(new FormData(form).get('email')).trim();
    setMessage(message, '');
    setBusy(button, true, 'Preparando…');
    try {
      await requestPasswordReset(email);
      form.reset();
      setMessage(message, 'La solicitud fue registrada. Si la cuenta existe, debe enviarse un enlace temporal de recuperación al usuario mediante el canal de entrega configurado.', 'success');
    } catch (error) {
      handleError(error, { target: message, fallback: 'No pudimos procesar la solicitud de recuperación.' });
    } finally {
      setBusy(button, false);
    }
  });
}

export function initResetPassword() {
  const token = getQueryParam('token');
  const form = $('#resetPasswordForm');
  const message = $('#formMessage');
  const submit = $('#resetPasswordButton');
  const tokenField = $('#resetToken');

  if (!token) {
    setMessage(message, 'El enlace de recuperación no contiene un token válido.');
    submit.disabled = true;
    return;
  }

  tokenField.value = token;
  form?.addEventListener('submit', async event => {
    event.preventDefault();
    const data = new FormData(form);
    const next = String(data.get('new_password'));
    const confirm = String(data.get('confirm_password'));
    setMessage(message, '');
    setBusy(submit, true, 'Restableciendo…');
    try {
      if (next.length < 8) throw new Error('La nueva contraseña debe tener al menos 8 caracteres.');
      if (next.length > 128) throw new Error('La nueva contraseña no puede superar 128 caracteres.');
      if (next !== confirm) throw new Error('Las contraseñas no coinciden.');
      await resetPasswordWithToken(token, next);
      form.reset();
      tokenField.value = '';
      setMessage(message, 'Contraseña restablecida correctamente. Todas las sesiones anteriores fueron revocadas. Ya puedes iniciar sesión.', 'success');
      submit.disabled = true;
    } catch (error) {
      handleError(error, { target: message, fallback: 'No pudimos restablecer la contraseña.' });
    } finally {
      if (!submit.disabled) setBusy(submit, false);
    }
  });
}
