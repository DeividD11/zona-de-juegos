import { requireAuth } from '../core/guards.js';
import { logout, revokeOtherSessions, changePassword, getToken } from '../core/session.js';
import { api } from '../core/api.js';
import { $, escapeHtml, formatDate, setBusy, setMessage, setFieldError } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { validatePassword, assertPasswordsMatch } from '../core/validators.js';

export async function initProfile() {
  const user = await requireAuth(); if (!user) return;
  $('#profileName').textContent = user.display_name;
  $('#profileEmail').textContent = user.email;
  $('#profileRole').textContent = user.role === 'admin' ? 'Administrador' : 'Jugador';
  $('#profileCreated').textContent = formatDate(user.created_at);

  $('#logoutButton')?.addEventListener('click', async () => {
    try { await logout(); } finally { location.href = '../login.html'; }
  });

  $('#revokeOtherSessionsButton')?.addEventListener('click', async () => {
    const button = $('#revokeOtherSessionsButton');
    const message = $('#sessionMessage');
    setMessage(message, '');
    setBusy(button, true, 'Cerrando…');
    try {
      const result = await revokeOtherSessions();
      const count = Number(result?.revoked_sessions) || 0;
      setMessage(message, count ? `Se cerraron ${count} sesión${count === 1 ? '' : 'es'} en otros dispositivos.` : 'No había otras sesiones activas.', 'success');
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No se pudieron cerrar las otras sesiones.' });
      if (appError.code === 'SESSION_EXPIRED') location.href = '../login.html';
    } finally {
      setBusy(button, false);
    }
  });

  $('#changePasswordForm')?.addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = $('#changePasswordButton');
    const message = $('#passwordMessage');
    const data = new FormData(form);
    setMessage(message, '');
    ['current_password','new_password','confirm_password'].forEach(id => setFieldError($('#'+id), $('#'+id+'Error')));
    setBusy(button, true, 'Actualizando…');
    try {
      const current = String(data.get('current_password'));
      const next = validatePassword(data.get('new_password'), { label: 'La nueva contraseña' });
      assertPasswordsMatch(next, data.get('confirm_password'));
      await changePassword(current, next);
      form.reset();
      setMessage(message, 'Contraseña actualizada. Las demás sesiones fueron revocadas.', 'success');
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No pudimos cambiar la contraseña.' });
      const fieldMap = { password: 'new_password', confirm_password: 'confirm_password', current_password: 'current_password' };
      const id = fieldMap[appError.field];
      if (id) setFieldError($('#'+id), $('#'+id+'Error'), appError.message);
      if (appError.code === 'SESSION_EXPIRED') location.href = '../login.html';
    } finally {
      setBusy(button, false);
    }
  });

  const scoreMessage = $('#profileScoresMessage');
  const loadScores = async () => {
    setMessage(scoreMessage, '');
    $('#profileScores').innerHTML = '<li class="loading-state">Cargando puntuaciones…</li>';
    try {
      const scores = await api.scores.listMine(getToken());
      $('#profileScores').innerHTML = scores.length
        ? scores.map(s => `<li><span>${escapeHtml(s.game_name)}</span><strong>${s.best_score}</strong></li>`).join('')
        : '<li><span>No tienes puntuaciones todavía.</span><strong>—</strong></li>';
    } catch (error) {
      handleError(error, { target: scoreMessage, fallback: 'No se pudieron cargar tus puntuaciones.', retry: loadScores });
    }
  };
  await loadScores();
}
