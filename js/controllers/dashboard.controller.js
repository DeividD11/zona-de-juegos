import { requireAuth } from '../core/guards.js';
import { logout } from '../models/auth.model.js';
import { listGames } from '../models/game.model.js';
import { getMyScores } from '../models/score.model.js';
import { renderGames, renderScores, renderUser, renderGamesLoading, renderScoresLoading } from '../views/dashboard.view.js';
import { $, setMessage } from '../core/utils.js';
import { handleError } from '../core/errors.js';

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
    try {
      const [games, scores] = await Promise.all([listGames(), getMyScores()]);
      renderGames(games);
      renderScores(scores);
    } catch (error) {
      const appError = handleError(error, {
        target: message,
        fallback: 'No pudimos cargar tu información.',
        retry: load
      });
      if (appError.code === 'SESSION_EXPIRED') location.href = 'login.html';
    }
  };
  await load();
}
