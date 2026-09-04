export const DIRECTIONS = Object.freeze({
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
  left: { x: -1, y: 0 },
  right: { x: 1, y: 0 }
});

export function createInitialState(size = 20) {
  const center = Math.floor(size / 2);
  return {
    size,
    snake: [{ x: center, y: center }, { x: center - 1, y: center }, { x: center - 2, y: center }],
    direction: { ...DIRECTIONS.right },
    nextDirection: { ...DIRECTIONS.right },
    food: randomFood([{ x: center, y: center }, { x: center - 1, y: center }, { x: center - 2, y: center }], size),
    score: 0,
    running: false,
    gameOver: false
  };
}

export function randomFood(snake, size) {
  const free = [];
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    if (!snake.some(part => part.x === x && part.y === y)) free.push({ x, y });
  }
  return free[Math.floor(Math.random() * free.length)] || null;
}

export function step(state) {
  const direction = state.nextDirection;
  const head = state.snake[0];
  const next = { x: head.x + direction.x, y: head.y + direction.y };
  const hitWall = next.x < 0 || next.y < 0 || next.x >= state.size || next.y >= state.size;
  const eating = state.food && next.x === state.food.x && next.y === state.food.y;
  const bodyToCheck = eating ? state.snake : state.snake.slice(0, -1);
  const hitSelf = bodyToCheck.some(part => part.x === next.x && part.y === next.y);

  if (hitWall || hitSelf) return { ...state, running: false, gameOver: true };

  const snake = [next, ...state.snake];
  if (!eating) snake.pop();
  const score = eating ? state.score + 10 : state.score;
  const food = eating ? randomFood(snake, state.size) : state.food;

  return { ...state, snake, direction, food, score, running: true };
}
