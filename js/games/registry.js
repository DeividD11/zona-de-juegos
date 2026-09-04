import { SnakeController } from './snake/snake.controller.js';

/**
 * Registro único de juegos. El controlador central solo resuelve slug -> controlador.
 * Cada juego mantiene internamente su propia lógica MVC.
 */
export const GameRegistry = Object.freeze({
  snake: SnakeController
});
