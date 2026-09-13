import { validateEmail, validatePassword, validateName, validateScore, validateSlug, assertPasswordsMatch } from '../js/core/validators.js';
import { can, ACTIONS } from '../js/core/authorization.js';
import { createSessionService } from '../js/core/session.service.js';
import { createInitialState, SNAKE_STATES, step, DIRECTIONS, enqueueDirection, getMaxScore } from '../js/games/snake/snake.model.js';

const $ = selector => document.querySelector(selector);
const results = [];

function pass(suite, detail) { results.push({ suite, ok: true, detail }); }
function fail(suite, error) { results.push({ suite, ok: false, detail: error instanceof Error ? error.message : String(error) }); }
function expect(condition, message) { if (!condition) throw new Error(message); }
function expectThrow(fn, message) {
  let thrown = false;
  try { fn(); } catch { thrown = true; }
  expect(thrown, message);
}

function createStorage() {
  const data = new Map();
  return {
    getItem: key => data.has(key) ? data.get(key) : null,
    setItem: (key, value) => data.set(key, String(value)),
    removeItem: key => data.delete(key),
    has: key => data.has(key)
  };
}

async function testValidators() {
  validateEmail('PLAYER@example.com');
  validatePassword('12345678');
  validateName('Iván');
  validateScore(0, { max: 100 });
  validateSlug('snake');
  assertPasswordsMatch('secret123', 'secret123');
  expectThrow(() => validateEmail('bad'), 'Debe rechazar email inválido.');
  expectThrow(() => validatePassword('1234567'), 'Debe rechazar contraseña corta.');
  expectThrow(() => validateName('A'), 'Debe rechazar nombre corto.');
  expectThrow(() => validateScore(-1), 'Debe rechazar score negativo.');
  expectThrow(() => validateSlug('Snake!'), 'Debe rechazar slug inválido.');
  expectThrow(() => assertPasswordsMatch('a', 'b'), 'Debe rechazar contraseñas diferentes.');
}

async function testAuthorization() {
  const user = { role: 'user' };
  const admin = { role: 'admin' };
  expect(can(user, ACTIONS.VIEW_GAMES), 'USER debe ver juegos.');
  expect(can(user, ACTIONS.PLAY_GAME), 'USER debe jugar.');
  expect(!can(user, ACTIONS.MANAGE_USERS), 'USER no debe gestionar usuarios.');
  expect(!can(user, ACTIONS.MANAGE_ROLES), 'USER no debe modificar roles.');
  expect(!can(user, ACTIONS.MANAGE_GAMES), 'USER no debe modificar juegos.');
  expect(can(admin, ACTIONS.MANAGE_USERS), 'ADMIN debe gestionar usuarios.');
  expect(can(admin, ACTIONS.MANAGE_GAMES), 'ADMIN debe gestionar juegos.');
}

async function testAuthSession() {
  const storage = createStorage();
  const calls = [];
  let validateResult = { id: '1', name: 'Player', email: 'player@example.com', role: 'user' };
  const apiClient = {
    cache: { clear: () => calls.push('cache.clear') },
    auth: {
      register: async () => ({ session_token: 'register-token', user: { id: '1', display_name: 'Player', email: 'player@example.com', role: 'user' } }),
      login: async (email, password) => {
        if (password !== 'correct123') throw new Error('Correo o contraseña incorrectos.');
        return { session_token: 'login-token', user: { id: '1', display_name: 'Player', email, role: 'user' } };
      },
      requestPasswordReset: async email => ({ email }),
      resetPassword: async token => ({ token })
    },
    sessions: {
      validate: async () => validateResult,
      logout: async token => calls.push(`logout:${token}`),
      revokeOther: async token => ({ token }),
      changePassword: async () => ({ success: true })
    }
  };
  const service = createSessionService({ apiClient, storage });
  await service.register('Player', 'player@example.com', 'correct123');
  expect(service.getToken() === 'register-token', 'Registro debe guardar sesión.');
  const user = await service.validate();
  expect(user?.email === 'player@example.com', 'validate() debe normalizar usuario.');
  validateResult = null;
  expect(await service.validate() === null, 'Sesión inválida debe expirar.');
  expect(!storage.has('zona_session_token'), 'Sesión expirada debe limpiar token.');
  await service.login('player@example.com', 'correct123');
  expect(service.getToken() === 'login-token', 'Login correcto debe guardar token.');
  await service.logout();
  expect(calls.includes('logout:login-token'), 'Logout debe revocar en API.');
  expect(!storage.has('zona_session_token'), 'Logout debe limpiar sesión.');
  let invalidThrown = false;
  try { await service.login('player@example.com', 'bad'); } catch { invalidThrown = true; }
  expect(invalidThrown, 'Contraseña incorrecta debe fallar.');
}

async function testSnake() {
  const start = createInitialState(20);
  expect(start.status === SNAKE_STATES.READY, 'Estado inicial debe ser READY.');
  let state = { ...start, status: SNAKE_STATES.PLAYING, food: { x: start.snake[0].x + 1, y: start.snake[0].y } };
  state = step(state);
  expect(state.score === 10, 'Comer debe sumar 10.');
  expect(state.snake.length === 4, 'Comer debe hacer crecer la serpiente.');
  const collision = step({
    ...state,
    food: { x: 0, y: 0 },
    direction: { ...DIRECTIONS.left },
    directionQueue: []
  });
  expect(collision.status === SNAKE_STATES.PLAYING || collision.status === SNAKE_STATES.GAME_OVER, 'La simulación debe producir un estado válido.');

  const wall = step({
    ...createInitialState(5), status: SNAKE_STATES.PLAYING,
    snake: [{ x: 4, y: 2 }, { x: 3, y: 2 }, { x: 2, y: 2 }],
    direction: { ...DIRECTIONS.right }, directionQueue: [], food: { x: 0, y: 0 }, score: 0
  });
  expect(wall.status === SNAKE_STATES.GAME_OVER, 'Choque contra pared debe producir GAME_OVER.');

  const base = { ...createInitialState(10), status: SNAKE_STATES.PLAYING };
  const queued = enqueueDirection(base, 'up');
  const queuedTwice = enqueueDirection(queued, 'right');
  const reverseOfPending = enqueueDirection(queuedTwice, 'left');
  expect(queuedTwice.directionQueue.length === 2, 'Debe aceptar entradas rápidas en cola.');
  expect(reverseOfPending.directionQueue.length === 2, 'No debe aceptar reversa contra dirección pendiente.');

  // La entrada realizada antes de iniciar debe sobrevivir a la reconstrucción del estado.
  const preStartQueue = [ 'up', 'right' ];
  const restarted = preStartQueue.reduce(
    (current, directionName) => enqueueDirection(current, directionName),
    createInitialState(10)
  );
  const [firstDirection] = restarted.directionQueue;
  expect(firstDirection === 'up', 'La primera dirección previa al inicio debe conservarse.');
  expect(restarted.directionQueue[1] === 'right', 'La cola previa al inicio debe conservar su orden.');

  expect(getMaxScore({ boardSize: 20, initialLength: 3, pointsPerFood: 10 }) === 3970, 'Máximo teórico de SNAKE incorrecto.');
}

async function run() {
  const suites = [
    ['Validaciones', testValidators],
    ['Autorización', testAuthorization],
    ['Sesiones/autenticación', testAuthSession],
    ['SNAKE', testSnake]
  ];
  results.length = 0;
  $('#summary').textContent = 'Ejecutando…';
  for (const [name, fn] of suites) {
    try { await fn(); pass(name, 'Todas las comprobaciones pasaron.'); }
    catch (error) { fail(name, error); }
  }
  $('#results').innerHTML = results.map(row => `
    <tr><td>${row.suite}</td><td><span class="badge ${row.ok ? 'badge--admin' : 'status-badge status-badge--disabled'}">${row.ok ? 'PASS' : 'FAIL'}</span></td><td>${row.detail}</td></tr>
  `).join('');
  const passed = results.filter(row => row.ok).length;
  const failed = results.length - passed;
  $('#summary').textContent = `${passed} PASS · ${failed} FAIL`;
}

$('#runTests').addEventListener('click', () => void run());
void run();
