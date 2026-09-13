/**
 * Registro único de juegos. Cada juego se carga bajo demanda.
 * Contrato conceptual común: mount, bindEvents, unbindEvents, init, start,
 * pause, resume, restart, destroy, getScore y getState.
 */
import { assertGameContract } from './game.contract.js';

export const GameRegistry = Object.freeze({
  snake: async () => (await import('./snake/snake.controller.js')).SnakeController,
  tetris: async () => (await import('./tetris/tetris.controller.js')).TetrisController,
  pong: async () => (await import('./pong/pong.controller.js')).PongController,
  memory: async () => (await import('./memory/memory.controller.js')).MemoryController,
  minesweeper: async () => (await import('./minesweeper/minesweeper.controller.js')).MinesweeperController
});

export async function getGameController(slug) {
  const loader = GameRegistry[slug];
  if (!loader) return null;
  const GameController = await loader();
  return assertGameContract(GameController);
}
