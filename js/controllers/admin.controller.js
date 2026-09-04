import { requireAdmin } from '../core/guards.js';
import { logout } from '../models/auth.model.js';
import { getAdminData, setGameActive, setUserRole } from '../models/user.model.js';
import { $, setBusy, setMessage } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { renderAdmin, renderAdminLoading } from '../views/admin.view.js';

export async function initAdmin() {
  const actor = await requireAdmin();
  if (!actor) return;
  $('#logoutButton')?.addEventListener('click', async () => { try { await logout(); } finally { location.href = 'login.html'; } });

  let loading = false;
  const refresh = async () => {
    if (loading) return;
    loading = true;
    const message = $('#adminMessage');
    message.hidden = true;
    renderAdminLoading();
    try {
      const data = await getAdminData();
      renderAdmin(data, actor);
      bindActions();
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No pudimos cargar la administración.', retry: refresh });
      if (appError.code === 'SESSION_EXPIRED') location.href = 'login.html';
    } finally {
      loading = false;
    }
  };

  const bindActions = () => {
    document.querySelectorAll('.role-select').forEach(select => select.addEventListener('change', async event => {
      select.disabled = true;
      try {
        await setUserRole(select.dataset.userId, event.target.value);
        await refresh();
      } catch (error) {
        handleError(error, { target: $('#adminMessage'), fallback: 'No pudimos actualizar el rol.' });
        select.disabled = false;
      }
    }));
    document.querySelectorAll('.game-toggle').forEach(button => button.addEventListener('click', async () => {
      setBusy(button, true, 'Guardando…');
      try {
        await setGameActive(button.dataset.gameId, button.dataset.nextActive === 'true');
        await refresh();
      } catch (error) {
        handleError(error, { target: $('#adminMessage'), fallback: 'No pudimos actualizar el juego.' });
        setBusy(button, false);
      }
    }));
  };

  await refresh();
}
