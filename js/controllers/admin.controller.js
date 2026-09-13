import { requireAdmin } from '../core/guards.js';
import { logout } from '../core/session.js';
import { api } from '../core/api.js';
import { getToken } from '../core/session.js';
import { $, setBusy } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { renderAdminLoading, renderUsers, renderGames, renderScores, renderSessions, renderAudit } from '../views/admin.view.js';

const PAGE_SIZE = 20;

export async function initAdmin() {
  const actor = await requireAdmin();
  if (!actor) return;
  $('#logoutButton')?.addEventListener('click', async () => { try { await logout(); } finally { location.href = 'login.html'; } });

  const state = { users: 1, scores: 1, sessions: 1, audit: 1 };
  let loading = false;

  const load = async () => {
    if (loading) return;
    loading = true;
    const message = $('#adminMessage');
    message.hidden = true;
    renderAdminLoading();
    try {
      const [u, g, s, ss, a] = await Promise.all([
        api.admin.usersPage(getToken(), state.users, PAGE_SIZE), api.admin.games(getToken()), api.admin.scoresPage(getToken(), state.scores, PAGE_SIZE), api.admin.sessionsPage(getToken(), state.sessions, PAGE_SIZE), api.admin.auditPage(getToken(), state.audit, PAGE_SIZE)
      ]);
      state.users = Number(u.page) || 1;
      state.scores = Number(s.page) || 1;
      state.sessions = Number(ss.page) || 1;
      state.audit = Number(a.page) || 1;
      renderUsers(u, actor); renderGames(g); renderScores(s); renderSessions(ss); renderAudit(a);
      bindActions();
    } catch (error) {
      const appError = handleError(error, { target: message, fallback: 'No pudimos cargar la administración.', retry: load });
      if (appError.code === 'SESSION_EXPIRED') location.href = 'login.html';
    } finally { loading = false; }
  };

  const bindActions = () => {
    document.querySelectorAll('[data-pager]').forEach(button => button.addEventListener('click', () => {
      const key = button.dataset.pager;
      state[key] = Math.max(1, Number(button.dataset.page) || 1);
      void load();
    }, { once: true }));
    document.querySelectorAll('.role-select').forEach(select => select.addEventListener('change', async event => {
      select.disabled = true;
      try { await api.admin.setUserRole(getToken(), select.dataset.userId, event.target.value); await load(); }
      catch (error) { handleError(error, { target: $('#adminMessage'), fallback: 'No pudimos actualizar el rol.' }); select.disabled = false; }
    }));
    document.querySelectorAll('.game-toggle').forEach(button => button.addEventListener('click', async () => {
      setBusy(button, true, 'Guardando…');
      try { await api.admin.setGameActive(getToken(), button.dataset.gameId, button.dataset.nextActive === 'true'); await load(); }
      catch (error) { handleError(error, { target: $('#adminMessage'), fallback: 'No pudimos actualizar el juego.' }); setBusy(button, false); }
    }));
  };

  await load();
}
