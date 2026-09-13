/**
 * Contrato conceptual común para cualquier juego registrado.
 * Cada controlador debe ofrecer este lifecycle. Los métodos pueden ser
 * síncronos o devolver Promise cuando la partida dependa de recursos externos.
 */
export const GAME_LIFECYCLE = Object.freeze([
  'init',
  'start',
  'pause',
  'resume',
  'restart',
  'destroy',
  'getScore',
  'getState'
]);

export function assertGameContract(GameController) {
  const prototype = GameController?.prototype;
  if (!prototype) throw new TypeError('Controlador de juego inválido.');
  for (const method of GAME_LIFECYCLE) {
    if (typeof prototype[method] !== 'function') {
      throw new TypeError(`El juego no implementa ${method}().`);
    }
  }
  return GameController;
}
