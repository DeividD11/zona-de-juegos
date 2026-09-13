import { bindAuth } from '../views/auth.view.js';
import { login, register, validate } from '../core/session.js';
import { setBusy, setMessage, setFieldError, $ } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { ROUTES } from '../core/constants.js';
import { validateEmail, validateName, validatePassword, assertPasswordsMatch } from '../core/validators.js';

export async function initLogin() {
  if (await validate()) { location.href = ROUTES.dashboard; return; }
  bindAuth('#loginForm', async data => {
    const button = $('#loginSubmit');
    const message = $('#formMessage');
    setMessage(message, '');
    setFieldError($('#email'), $('#emailError'));
    setFieldError($('#password'), $('#passwordError'));
    setBusy(button, true, 'Entrando…');
    try {
      const email = validateEmail(data.get('email'));
      const password = String(data.get('password'));
      await login(email, password);
      location.href = ROUTES.dashboard;
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No se pudo iniciar sesión.' });
      setFieldError(appError.field === 'email' ? $('#email') : null, $('#emailError'), appError.field === 'email' ? appError.message : '');
      setFieldError(appError.field === 'password' ? $('#password') : null, $('#passwordError'), appError.field === 'password' ? appError.message : '');
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
    ['display_name','email','password','confirm_password'].forEach(id => {
      setFieldError($('#'+id), $('#'+id+'Error'));
    });
    setBusy(button, true, 'Creando cuenta…');
    try {
      const password = validatePassword(data.get('password'));
      const confirm = String(data.get('confirm_password'));
      assertPasswordsMatch(password, confirm);
      await register(validateName(data.get('display_name')), validateEmail(data.get('email')), password);
      location.href = ROUTES.dashboard;
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No se pudo crear la cuenta.' });
      const fieldMap = { display_name: 'display_name', email: 'email', password: 'password', confirm_password: 'confirm_password' };
      const id = fieldMap[appError.field];
      if (id) setFieldError($('#'+id), $('#'+id+'Error'), appError.message);
      setBusy(button, false);
    }
  });
}
