import { requireAuth } from '../core/guards.js';
import { logout, revokeOtherSessions, changePassword } from '../models/auth.model.js';
import { getMyScores } from '../models/score.model.js';
import { $, escapeHtml, formatDate, setBusy, setMessage } from '../core/utils.js';
import { handleError } from '../core/errors.js';

function validateNewPassword(password, confirm) {
  if (password.length < 8) throw new Error('La nueva contraseña debe tener al menos 8 caracteres.');
  if (password.length > 128) throw new Error('La nueva contraseña no puede superar 128 caracteres.');
  if (password !== confirm) throw new Error('Las nuevas contraseñas no coinciden.');
}

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
      setMessage(message, count
        ? `Se cerraron ${count} sesión${count === 1 ? '' : 'es'} en otros dispositivos.`
        : 'No había otras sesiones activas.', 'success');
    } catch (error) {
      handleError(error, { target: message, fallback: 'No se pudieron cerrar las otras sesiones.' });
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
    setBusy(button, true, 'Actualizando…');
    try {
      const current = String(data.get('current_password'));
      const next = String(data.get('new_password'));
      const confirm = String(data.get('confirm_password'));
      validateNewPassword(next, confirm);
      await changePassword(current, next);
      form.reset();
      setMessage(message, 'Contraseña actualizada. Las demás sesiones fueron revocadas.', 'success');
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No pudimos cambiar la contraseña.' });
      if (appError.code === 'SESSION_EXPIRED') location.href = '../login.html';
    } finally {
      setBusy(button, false);
    }
  });

  const scoreMessage = $('#profileScoresMessage');
  const loadScores = async () => {
    scoreMessage.hidden = true;
    $('#profileScores').innerHTML = '<li class="loading-state">Cargando puntuaciones…</li>';
    try {
      const scores = await getMyScores();
      $('#profileScores').innerHTML = scores.length
        ? scores.map(s => `<li><span>${escapeHtml(s.game_name)}</span><strong>${s.best_score}</strong></li>`).join('')
        : '<li><span>No tienes puntuaciones todavía.</span><strong>—</strong></li>';
    } catch (error) {
      handleError(error, { target: scoreMessage, fallback: 'No se pudieron cargar tus puntuaciones.', retry: loadScores });
    }
  };
  await loadScores();
}
