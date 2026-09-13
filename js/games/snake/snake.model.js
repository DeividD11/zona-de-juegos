export const SNAKE_CONFIG = Object.freeze({
  version: '1.1.0',
  boardSize: 20,
  initialLength: 3,
  pointsPerFood: 10,
  tickMs: 110
});

export const DIRECTIONS = Object.freeze({
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
  left: { x: -1, y: 0 },
  right: { x: 1, y: 0 }
});

export const SNAKE_STATES = Object.freeze({
  READY: 'READY',
  PLAYING: 'PLAYING',
  PAUSED: 'PAUSED',
  GAME_OVER: 'GAME_OVER',
  DESTROYED: 'DESTROYED'
});

export function getMaxScore({ boardSize = SNAKE_CONFIG.boardSize, initialLength = SNAKE_CONFIG.initialLength, pointsPerFood = SNAKE_CONFIG.pointsPerFood } = {}) {
  const cells = boardSize * boardSize;
  return Math.max(0, (cells - initialLength) * pointsPerFood);
}

export function createInitialState(size = SNAKE_CONFIG.boardSize) {
  const center = Math.floor(size / 2);
  const initialLength = Math.min(SNAKE_CONFIG.initialLength, Math.max(1, size - 1));
  const snake = Array.from({ length: initialLength }, (_, index) => ({
    x: center - index,
    y: center
  }));
  return {
    size,
    snake,
    direction: { ...DIRECTIONS.right },
    directionQueue: [],
    food: randomFood(snake, size),
    score: 0,
    status: SNAKE_STATES.READY
  };
}

export function randomFood(snake, size) {
  const occupied = new Set(snake.map(part => `${part.x}:${part.y}`));
  const free = [];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (!occupied.has(`${x}:${y}`)) free.push({ x, y });
    }
  }
  return free[Math.floor(Math.random() * free.length)] || null;
}

export function enqueueDirection(state, directionName, maxQueue = 3) {
  const next = DIRECTIONS[directionName];
  if (!next || state.status === SNAKE_STATES.GAME_OVER || state.status === SNAKE_STATES.DESTROYED) return state;

  const pending = state.directionQueue;
  const comparison = pending.length ? DIRECTIONS[pending[pending.length - 1]] : state.direction;
  if (next.x === -comparison.x && next.y === -comparison.y) return state;
  if (pending[pending.length - 1] === directionName || (pending.length === 0 && directionName === vectorToName(state.direction))) return state;
  if (pending.length >= maxQueue) return state;

  return { ...state, directionQueue: [...pending, directionName] };
}

function vectorToName(direction) {
  return Object.entries(DIRECTIONS).find(([, vector]) => vector.x === direction.x && vector.y === direction.y)?.[0] || '';
}

export function step(state) {
  if (state.status !== SNAKE_STATES.PLAYING) return state;

  const [queuedName, ...remainingQueue] = state.directionQueue;
  const direction = queuedName ? { ...DIRECTIONS[queuedName] } : { ...state.direction };
  const head = state.snake[0];
  const next = { x: head.x + direction.x, y: head.y + direction.y };
  const hitWall = next.x < 0 || next.y < 0 || next.x >= state.size || next.y >= state.size;
  const eating = Boolean(state.food && next.x === state.food.x && next.y === state.food.y);
  const bodyToCheck = eating ? state.snake : state.snake.slice(0, -1);
  const hitSelf = bodyToCheck.some(part => part.x === next.x && part.y === next.y);

  if (hitWall || hitSelf) {
    return { ...state, direction, directionQueue: remainingQueue, status: SNAKE_STATES.GAME_OVER };
  }

  const snake = [next, ...state.snake];
  if (!eating) snake.pop();
  const score = eating ? state.score + SNAKE_CONFIG.pointsPerFood : state.score;
  const food = eating ? randomFood(snake, state.size) : state.food;

  return { ...state, snake, direction, directionQueue: remainingQueue, food, score, status: SNAKE_STATES.PLAYING };
}
