import { requireAuth } from '../core/guards.js';
import { api } from '../core/api.js';
import { getToken } from '../core/session.js';
import { renderGameLoading, renderGameShell, renderUnavailable, renderGameError } from '../views/game.view.js';
import { getQueryParam } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { validateSlug, validateScore } from '../core/validators.js';
import { getGameController } from '../games/registry.js';

let activeGame = null;

export async function initGame() {
  renderGameLoading();
  if (activeGame) {
    activeGame.destroy();
    activeGame = null;
  }

  const user = await requireAuth();
  if (!user) return;

  let slug;
  try {
    slug = validateSlug(getQueryParam('game') || 'snake');
  } catch {
    renderUnavailable('juego inválido');
    return;
  }

  try {
    const games = await api.games.catalog(getToken());
    const game = games.find(item => item.slug === slug);
    const GameController = await getGameController(slug);

    if (!game || !GameController) {
      renderUnavailable(slug);
      return;
    }

    renderGameShell(game);
    const best = Number(game.best_score) || 0;

    activeGame = new GameController(document.querySelector('#gameApp'), {
      bestScore: best,
      onStart: gameVersion => api.gameSessions.start(getToken(), slug, gameVersion),
      onScore: (sessionId, score, options = {}) => {
        if (!sessionId) throw new Error('La partida no tiene una sesión válida.');
        const safeScore = validateScore(score, Number.isSafeInteger(options.maxScore) ? { min: 0, max: options.maxScore } : undefined);
        return api.scores.save(getToken(), sessionId, safeScore, options.metadata || {});
      }
    });

    activeGame.mount();
  } catch (error) {
    const appError = handleError(error, {
      target: document.querySelector('#gameMessage'),
      fallback: 'No se pudo cargar el juego.',
      retry: () => initGame()
    });
    renderGameError('Revisa tu conexión e inténtalo de nuevo.', () => initGame());
    if (appError.code === 'SESSION_EXPIRED') location.href = '../login.html';
  }
}

export function destroyGame() {
  if (!activeGame) return;
  activeGame.destroy();
  activeGame = null;
}
