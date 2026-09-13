import { requireAuth } from '../core/guards.js';
import { logout } from '../core/session.js';
import { api } from '../core/api.js';
import { getToken } from '../core/session.js';
import { renderGames, renderScores, renderUser, renderGamesLoading, renderGamesError, renderScoresLoading } from '../views/dashboard.view.js';
import { $ } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { announce } from '../core/a11y.js';

export async function initDashboard() {
  const user = await requireAuth(); if (!user) return;
  renderUser(user);
  $('#logoutButton')?.addEventListener('click', async () => { try { await logout(); } finally { location.href = 'login.html'; } });
  if (user.role === 'admin') $('#adminLink').hidden = false;

  const load = async () => {
    const message = $('#dashboardMessage');
    message.hidden = true;
    renderGamesLoading();
    renderScoresLoading();
    announce('Cargando catálogo y tus puntuaciones.');
    try {
      const [games, scores] = await Promise.all([api.games.catalog(getToken()), api.scores.listMine(getToken())]);
      renderGames(games, load);
      renderScores(scores);
      announce('Catálogo y puntuaciones cargados.');
    } catch (error) {
      const appError = handleError(error, {
        target: message,
        fallback: 'No pudimos cargar tu información.',
        retry: load
      });
      renderGamesError(load);
      if (appError.code === 'SESSION_EXPIRED') location.href = 'login.html';
    }
  };
  await load();
}
