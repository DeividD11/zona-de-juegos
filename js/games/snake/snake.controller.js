import { createInitialState, DIRECTIONS, enqueueDirection, getMaxScore, SNAKE_CONFIG, SNAKE_STATES, step } from './snake.model.js';
import { SnakeView } from './snake.view.js';
import { toAppError } from '../../core/errors.js';
import { announce } from '../../core/a11y.js';

export class SnakeController {
  constructor(root, { bestScore = 0, onStart = async () => ({}), onScore = async () => {} } = {}) {
    this.root = root;
    this.view = new SnakeView(root);
    this.bestScore = Number(bestScore) || 0;
    this.onStart = onStart;
    this.onScore = onScore;
    this.timer = null;
    this.sessionId = null;
    this.state = createInitialState();
    this.mounted = false;
    this.destroyed = false;
    this.submittingScore = false;
    this.startedAt = null;
    this.pendingScore = null;

    this.keyHandler = event => {
      const map = {
        ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
        w: 'up', s: 'down', a: 'left', d: 'right',
        W: 'up', S: 'down', A: 'left', D: 'right'
      };
      const direction = map[event.key];
      if (direction) {
        event.preventDefault();
        this.changeDirection(direction);
      }
      if (event.key === 'Escape' || event.key === ' ') {
        event.preventDefault();
        if (this.state.status === SNAKE_STATES.PLAYING) this.pause();
        else if (this.state.status === SNAKE_STATES.PAUSED) this.resume();
      }
    };
    this.resizeHandler = () => this.view.requestResize(this.state.size);
    this.orientationHandler = () => this.view.requestResize(this.state.size);
  }

  init() { return this.mount(); }

  mount() {
    if (this.mounted || this.destroyed) return this;
    this.mounted = true;
    this.bindEvents();
    this.view.resize(this.state.size);
    this.view.render(this.state);
    this.renderBest();
    return this;
  }

  bindEvents() {
    this.view.bindStart(() => void this.start());
    this.view.bindPause(() => this.pause());
    this.view.bindResume(() => this.resume());
    this.view.bindRestart(() => void this.restart());
    this.view.bindRetry(() => void this.retryScoreOrRestart());
    this.view.bindDirection(dir => this.changeDirection(dir));
    window.addEventListener('keydown', this.keyHandler);
    window.addEventListener('resize', this.resizeHandler);
    window.visualViewport?.addEventListener('resize', this.resizeHandler);
    window.addEventListener('orientationchange', this.orientationHandler);
  }

  unbindEvents() {
    this.view.unbindEvents();
    window.removeEventListener('keydown', this.keyHandler);
    window.removeEventListener('resize', this.resizeHandler);
    window.visualViewport?.removeEventListener('resize', this.resizeHandler);
    window.removeEventListener('orientationchange', this.orientationHandler);
  }

  async start() {
    if (this.destroyed || this.submittingScore) return null;
    if (this.state.status === SNAKE_STATES.PLAYING) return null;

    const requestedDirections = [...(this.state.directionQueue || [])];
    const nextState = requestedDirections.reduce(
      (currentState, directionName) => enqueueDirection(currentState, directionName),
      createInitialState(this.state.size)
    );

    clearInterval(this.timer);
    this.timer = null;
    this.sessionId = null;
    this.startedAt = new Date();

    this.view.setStatus('Preparando la partida…');
    announce('Preparando la partida.');
    this.view.setSaveStatus('');

    try {
      const session = await this.onStart(SNAKE_CONFIG.version);
      this.sessionId = session?.game_session_id || null;
      if (!this.sessionId) throw new Error('No se pudo iniciar la partida.');

      const [queued, ...remainingQueue] = nextState.directionQueue;
      this.state = queued
        ? {
            ...nextState,
            direction: { ...DIRECTIONS[queued] },
            directionQueue: remainingQueue,
            status: SNAKE_STATES.PLAYING
          }
        : { ...nextState, status: SNAKE_STATES.PLAYING };

      this.view.render(this.state);
      this.startTimer();
      return session;
    } catch (error) {
      this.state = {
        ...this.state,
        status: SNAKE_STATES.READY
      };
      this.startedAt = null;
      this.view.render(this.state);
      const appError = toAppError(error, 'No se pudo iniciar la partida.');
      this.view.setStatus(appError.message);
      announce(appError.message, { politeness: 'assertive' });
      throw error;
    }
  }

  startTimer() {
    clearInterval(this.timer);
    this.timer = setInterval(() => this.tick(), SNAKE_CONFIG.tickMs);
  }

  pause() {
    if (this.destroyed || this.state.status !== SNAKE_STATES.PLAYING) return;
    clearInterval(this.timer);
    this.timer = null;
    this.state = { ...this.state, status: SNAKE_STATES.PAUSED };
    this.view.render(this.state);
  }

  resume() {
    if (this.destroyed || this.state.status !== SNAKE_STATES.PAUSED || !this.sessionId) return;
    this.state = { ...this.state, status: SNAKE_STATES.PLAYING };
    this.view.render(this.state);
    this.startTimer();
  }

  async restart() {
    if (this.destroyed) return null;
    clearInterval(this.timer);
    this.timer = null;
    this.sessionId = null;
    this.startedAt = null;
    this.submittingScore = false;
    this.state = createInitialState(this.state.size);
    this.view.render(this.state);
    return this.start();
  }

  tick() {
    if (!this.sessionId || this.state.status !== SNAKE_STATES.PLAYING) return;
    this.state = step(this.state);
    this.view.render(this.state);
    if (this.state.status !== SNAKE_STATES.GAME_OVER) return;

    clearInterval(this.timer);
    this.timer = null;

    const sessionId = this.sessionId;
    this.sessionId = null;

    const endTime = new Date();
    const startTime = this.startedAt || endTime;
    const durationSeconds = Math.max(0, (endTime.getTime() - startTime.getTime()) / 1000);

    this.pendingScore = {
      sessionId,
      score: this.state.score,
      metadata: {
        start_time: startTime.toISOString(),
        end_time: endTime.toISOString(),
        duration: Number(durationSeconds.toFixed(3)),
        score: this.state.score,
        game_version: SNAKE_CONFIG.version
      }
    };

    this.renderBest();
    this.view.showGameOver(this.state.score, this.bestScore);
    void this.submitScore(
      sessionId,
      this.state.score,
      this.pendingScore.metadata
    );
  }

  async submitScore(sessionId, score, metadata) {
    this.submittingScore = true;
    this.view.setSaveStatus('Guardando puntuación…', 'saving');
    announce('Guardando puntuación.');
    try {
      const result = await this.onScore(sessionId, score, {
        maxScore: getMaxScore({ boardSize: this.state.size }),
        metadata
      });
      const serverBest = Number(result?.best_score);
      if (Number.isSafeInteger(serverBest)) this.bestScore = Math.max(this.bestScore, serverBest);
      this.renderBest();
      this.view.showGameOver(score, this.bestScore);
      this.pendingScore = null;
      this.view.setSaveStatus('✓ Puntuación guardada', 'success');
      announce('Puntuación guardada.');
    } catch (error) {
      const appError = toAppError(error, 'No pudimos guardar tu puntuación.');
      this.view.showGameOver(score, this.bestScore);
      this.view.setSaveStatus(`⚠ ${appError.message || 'No pudimos guardar tu puntuación.'}`, 'error');
      announce(appError.message || 'No pudimos guardar tu puntuación.', { politeness: 'assertive' });
    } finally {
      this.submittingScore = false;
    }
  }

  async retryScoreOrRestart() {
    if (this.destroyed || this.submittingScore) return;
    if (this.pendingScore) {
      await this.submitScore(
        this.pendingScore.sessionId,
        this.pendingScore.score,
        this.pendingScore.metadata
      );
      return;
    }
    await this.restart();
  }

  changeDirection(directionName) {
    if (this.destroyed) return;
    const next = DIRECTIONS[directionName];
    if (!next) return;

    if (this.state.status === SNAKE_STATES.READY) {
      this.state = enqueueDirection(this.state, directionName);
      this.view.render(this.state);
      void this.start();
      return;
    }

    if (this.state.status !== SNAKE_STATES.PLAYING && this.state.status !== SNAKE_STATES.PAUSED) return;
    this.state = enqueueDirection(this.state, directionName);
    this.view.render(this.state);
  }

  getScore() { return Number(this.state.score) || 0; }

  getState() {
    return {
      ...this.state,
      snake: this.state.snake.map(part => ({ ...part })),
      direction: { ...this.state.direction },
      directionQueue: [...this.state.directionQueue],
      food: this.state.food ? { ...this.state.food } : null
    };
  }

  renderBest() {
    const best = this.root.querySelector('#snakeBest');
    if (best) best.textContent = String(this.bestScore);
  }

  destroy() {
    if (this.destroyed) return;
    clearInterval(this.timer);
    this.timer = null;
    this.unbindEvents();
    this.sessionId = null;
    this.startedAt = null;
    this.pendingScore = null;
    this.state = { ...this.state, status: SNAKE_STATES.DESTROYED };
    this.destroyed = true;
    this.mounted = false;
  }
}
