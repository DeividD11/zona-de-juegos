import { requireAuth } from '../core/guards.js';
import { listGames } from '../models/game.model.js';
import { getMyScores, startGame, finishGame } from '../models/score.model.js';
import { renderGameShell, renderUnavailable } from '../views/game.view.js';
import { getQueryParam } from '../core/utils.js';
import { handleError } from '../core/errors.js';
import { GameRegistry } from '../games/registry.js';

export async function initGame() {
  const user = await requireAuth();
  if (!user) return;

  const slug = getQueryParam('game') || 'snake';
  try {
    const [games, previous] = await Promise.all([listGames(), getMyScores()]);
    const game = games.find(item => item.slug === slug);
    const GameController = GameRegistry[slug];

    if (!game || typeof GameController !== 'function') {
      renderUnavailable(slug);
      return;
    }

    renderGameShell(game);
    const best = previous.find(item => item.slug === slug)?.best_score || 0;
    new GameController(document.querySelector('#gameApp'), {
      bestScore: best,
      onStart: () => startGame(slug),
      onScore: (sessionId, score) => finishGame(sessionId, score)
    });
  } catch (error) {
    const appError = handleError(error, {
      target: document.querySelector('#gameMessage'),
      fallback: 'No se pudo cargar el juego.',
      retry: () => initGame()
    });
    if (appError.code === 'SESSION_EXPIRED') location.href = '../login.html';
  }
}
