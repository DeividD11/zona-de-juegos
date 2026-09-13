import { requestPasswordReset, resetPasswordWithToken } from '../core/session.js';
import { $, setBusy, setMessage, getQueryParam, setFieldError } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { validateEmail, validatePassword, assertPasswordsMatch } from '../core/validators.js';

export function initForgotPassword() {
  $('#forgotPasswordForm')?.addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = $('#forgotPasswordButton');
    const message = $('#formMessage');
    setMessage(message, '');
    setFieldError($('#email'), $('#emailError'));
    setBusy(button, true, 'Preparando…');
    try {
      await requestPasswordReset(validateEmail(new FormData(form).get('email')));
      form.reset();
      setMessage(message, 'La solicitud fue registrada. Si la cuenta existe, recibirás un enlace temporal de recuperación por correo. Revisa también tu carpeta de spam.', 'success');
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No pudimos procesar la solicitud de recuperación.' });
      if (appError.field === 'email') setFieldError($('#email'), $('#emailError'), appError.message);
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
      validatePassword(next, { label: 'La nueva contraseña' });
      assertPasswordsMatch(next, confirm);
      await resetPasswordWithToken(token, next);
      form.reset();
      tokenField.value = '';
      setMessage(message, 'Contraseña restablecida correctamente. Todas las sesiones anteriores fueron revocadas. Ya puedes iniciar sesión.', 'success');
      submit.disabled = true;
    } catch (error) {
      handleError(error, { target: message, fallback: 'No pudimos restablecer tu contraseña.' });
    } finally {
      if (!submit.disabled) setBusy(submit, false);
    }
  });
}
