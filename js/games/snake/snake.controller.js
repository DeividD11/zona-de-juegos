import { createInitialState, DIRECTIONS, step } from './snake.model.js';
import { SnakeView } from './snake.view.js';

export class SnakeController {
  constructor(root, { bestScore = 0, onStart = async () => ({}), onScore = async () => {} } = {}) {
    this.root = root;
    this.view = new SnakeView(root);
    this.bestScore = Number(bestScore) || 0;
    this.onStart = onStart;
    this.onScore = onScore;
    this.timer = null;
    this.starting = false;
    this.sessionId = null;
    this.state = createInitialState();
    this.view.bindStart(() => void this.start());
    this.view.bindDirection(dir => this.changeDirection(dir));
    this.keyHandler = event => {
      const map = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', w: 'up', s: 'down', a: 'left', d: 'right' };
      const direction = map[event.key];
      if (direction) {
        event.preventDefault();
        this.changeDirection(direction);
      }
    };
    this.resizeHandler = () => this.view.resize(this.state.size);
    window.addEventListener('keydown', this.keyHandler);
    window.addEventListener('resize', this.resizeHandler);
    this.view.resize(this.state.size);
    this.view.render(this.state);
    this.renderBest();
  }

  renderBest() {
    const best = this.root.querySelector('#snakeBest');
    if (best) best.textContent = String(this.bestScore);
  }

  async start() {
    if (this.starting) return;
    clearInterval(this.timer);
    this.starting = true;
    this.sessionId = null;
    this.view.setStatus('Preparando la partida…');
    try {
      const session = await this.onStart();
      this.sessionId = session.game_session_id;
      this.state = createInitialState(this.state.size);
      this.state.running = true;
      this.view.render(this.state);
      this.timer = setInterval(() => this.tick(), 110);
    } catch (error) {
      this.state = { ...this.state, running: false, gameOver: false };
      this.view.setStatus(error?.message || 'No se pudo iniciar la partida.');
    } finally {
      this.starting = false;
    }
  }

  tick() {
    if (!this.sessionId) return;
    this.state = step(this.state);
    this.view.render(this.state);
    if (this.state.gameOver) {
      clearInterval(this.timer);
      this.timer = null;
      const sessionId = this.sessionId;
      this.sessionId = null;
      this.bestScore = Math.max(this.bestScore, this.state.score);
      this.renderBest();
      void this.submitScore(sessionId, this.state.score);
    }
  }

  async submitScore(sessionId, score) {
    this.view.setStatus('Guardando puntuación…');
    try {
      const result = await this.onScore(sessionId, score);
      if (result?.best_score > this.bestScore) this.bestScore = result.best_score;
      this.renderBest();
      this.view.setStatus(`Game Over. Puntuación guardada: ${score}. Pulsa “Iniciar” para jugar otra vez.`);
    } catch (error) {
      this.view.setStatus(`Game Over. ${error?.message || 'No pudimos guardar tu puntuación.'}`);
    }
  }

  changeDirection(directionName) {
    const next = DIRECTIONS[directionName];
    if (!next || this.starting) return;
    const current = this.state.nextDirection;
    if (next.x === -current.x && next.y === -current.y) return;
    this.state.nextDirection = { ...next };
    if (!this.state.running && !this.state.gameOver) void this.start();
  }

  destroy() {
    clearInterval(this.timer);
    window.removeEventListener('keydown', this.keyHandler);
    window.removeEventListener('resize', this.resizeHandler);
  }
}
