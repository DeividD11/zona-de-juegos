import { $ } from '../../core/utils.js';

export class SnakeView {
  constructor(root) {
    this.root = root;
    this.boundHandlers = new Map();
    this.canvasSize = 0;
    this.boardSize = 0;
    this.lastState = null;
    this.resizeScheduled = false;
    this.resizeFrame = 0;
    this.frameBuffer = null;
    this.frameCtx = null;

    root.innerHTML = `
      <div class="snake-toolbar">
        <div><span>Puntuación</span><strong id="snakeScore">0</strong></div>
        <div><span>Mejor</span><strong id="snakeBest">0</strong></div>
        <div class="snake-actions">
          <button class="button button--small" id="snakeStart" type="button">Iniciar</button>
          <button class="button button--small button--ghost" id="snakePause" type="button">Pausar</button>
          <button class="button button--small button--ghost" id="snakeResume" type="button">Reanudar</button>
          <button class="button button--small button--ghost" id="snakeRestart" type="button">Reiniciar</button>
        </div>
      </div>
      <div class="snake-board-wrap">
        <canvas id="snakeCanvas" class="snake-canvas" role="img" aria-label="Tablero del juego SNAKE"></canvas>
      </div>
      <div class="snake-status" id="snakeStatus" role="status" aria-live="polite" aria-atomic="true">Pulsa “Iniciar” o una flecha para comenzar.</div>
      <p id="snakeCanvasHelp" class="sr-only">Usa las flechas, W A S D o los botones táctiles para mover la serpiente. Pulsa espacio o Escape para pausar y reanudar.</p>
      <div class="snake-controls" role="group" aria-label="Controles táctiles">
        <button type="button" data-dir="up" aria-label="Mover arriba">↑</button>
        <button type="button" data-dir="left" aria-label="Mover izquierda">←</button>
        <button type="button" data-dir="down" aria-label="Mover abajo">↓</button>
        <button type="button" data-dir="right" aria-label="Mover derecha">→</button>
      </div>
      <section id="snakeGameOver" class="snake-game-over" hidden aria-live="polite" aria-atomic="true">
        <p class="eyebrow">Partida terminada</p>
        <h2>GAME OVER</h2>
        <div class="snake-game-over__scores">
          <div><span>Puntuación</span><strong id="snakeFinalScore">0</strong></div>
          <div><span>Mejor puntuación</span><strong id="snakeFinalBest">0</strong></div>
        </div>
        <p id="snakeSaveStatus" class="snake-save-status" role="status" aria-live="polite" aria-atomic="true"></p>
        <div class="snake-game-over__actions">
          <button class="button button--primary" id="snakeRetry" type="button">Reintentar</button>
          <a class="button button--ghost" href="../dashboard.html">Volver a juegos</a>
        </div>
      </section>
    `;
    this.canvas = $('#snakeCanvas', root);
    this.canvas.setAttribute('aria-describedby', 'snakeCanvasHelp');
    this.ctx = this.canvas.getContext('2d', { alpha: false, desynchronized: true });
  }

  requestResize(size) {
    if (this.resizeScheduled) return;
    this.resizeScheduled = true;
    this.resizeFrame = requestAnimationFrame(() => {
      this.resizeScheduled = false;
      this.resizeFrame = 0;
      this.resize(size);
    });
  }

  resize(size) {
    const wrap = this.root.querySelector('.snake-board-wrap');
    const rect = wrap?.getBoundingClientRect();
    const viewport = window.visualViewport;
    const viewportWidth = viewport?.width || window.innerWidth || 320;
    const viewportHeight = viewport?.height || window.innerHeight || 480;
    const width = rect?.width || this.root.getBoundingClientRect().width || 320;
    const landscape = viewportWidth > viewportHeight;
    const heightLimit = landscape ? Math.max(180, viewportHeight - 280) : Number.POSITIVE_INFINITY;
    const cssSize = Math.max(180, Math.floor(Math.min(width, viewportWidth - 24, heightLimit, 680)));
    const dpr = Math.max(1, Math.min(window.devicePixelRatio || 1, 3));
    const pixelSize = Math.floor(cssSize * dpr);

    this.canvas.style.width = `${cssSize}px`;
    this.canvas.style.height = `${cssSize}px`;

    if (pixelSize !== this.canvas.width || pixelSize !== this.canvas.height || this.boardSize !== size) {
      this.canvas.width = pixelSize;
      this.canvas.height = pixelSize;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.canvasSize = cssSize;
      this.boardSize = size;
      this.buildBackground(cssSize, size);
      if (this.lastState) this.render(this.lastState, size);
    } else {
      this.canvasSize = cssSize;
    }
  }

  buildBackground(cssSize, size) {
    this.frameBuffer = document.createElement('canvas');
    const dpr = Math.max(1, Math.min(window.devicePixelRatio || 1, 3));
    this.frameBuffer.width = Math.floor(cssSize * dpr);
    this.frameBuffer.height = Math.floor(cssSize * dpr);
    this.frameCtx = this.frameBuffer.getContext('2d', { alpha: false });
    this.frameCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.frameCtx.fillStyle = '#0b1220';
    this.frameCtx.fillRect(0, 0, cssSize, cssSize);
    const cell = cssSize / size;
    this.frameCtx.strokeStyle = 'rgba(255,255,255,.05)';
    this.frameCtx.lineWidth = 1;
    for (let i = 0; i <= size; i++) {
      const point = i * cell;
      this.frameCtx.beginPath();
      this.frameCtx.moveTo(point, 0);
      this.frameCtx.lineTo(point, cssSize);
      this.frameCtx.stroke();
      this.frameCtx.beginPath();
      this.frameCtx.moveTo(0, point);
      this.frameCtx.lineTo(cssSize, point);
      this.frameCtx.stroke();
    }
  }

  render(state, size = 20) {
    if (!state || !this.ctx) return;
    this.lastState = state;
    if (this.canvasSize === 0 || this.boardSize !== size) this.resize(size);
    const px = this.canvasSize;
    const cell = px / size;
    const ctx = this.ctx;

    if (this.frameBuffer) ctx.drawImage(this.frameBuffer, 0, 0, px, px);
    else {
      ctx.fillStyle = '#0b1220';
      ctx.fillRect(0, 0, px, px);
    }

    if (state.food) {
      ctx.fillStyle = '#ef4444';
      ctx.beginPath();
      ctx.arc((state.food.x + 0.5) * cell, (state.food.y + 0.5) * cell, cell * 0.32, 0, Math.PI * 2);
      ctx.fill();
    }

    state.snake.forEach((part, index) => {
      ctx.fillStyle = index === 0 ? '#60a5fa' : '#3b82f6';
      const pad = cell * 0.11;
      ctx.fillRect(part.x * cell + pad, part.y * cell + pad, cell - pad * 2, cell - pad * 2);
    });

    $('#snakeScore', this.root).textContent = String(state.score);
    const messages = {
      READY: 'Pulsa “Iniciar” o una flecha para comenzar.',
      PLAYING: '¡En juego! Usa el teclado o los controles táctiles.',
      PAUSED: 'Partida en pausa. Pulsa “Reanudar” para continuar.',
      GAME_OVER: 'Partida terminada. Revisa el resultado.',
      DESTROYED: 'Partida cerrada.'
    };
    $('#snakeStatus', this.root).textContent = messages[state.status] || '';

    if (state.status === 'GAME_OVER') this.showGameOver(state.score, Number($('#snakeBest', this.root)?.textContent || 0));
    else this.hideGameOver();
  }

  showGameOver(score, bestScore) {
    $('#snakeFinalScore', this.root).textContent = String(score);
    $('#snakeFinalBest', this.root).textContent = String(bestScore);
    $('#snakeGameOver', this.root).hidden = false;
  }

  setSaveStatus(text, type = '') {
    const node = $('#snakeSaveStatus', this.root);
    node.textContent = text;
    node.className = `snake-save-status${type ? ` snake-save-status--${type}` : ''}`;
    const retry = $('#snakeRetry', this.root);
    if (retry) retry.textContent = type === 'error' ? 'Reintentar guardado' : 'Volver a jugar';
  }

  hideGameOver() {
    $('#snakeGameOver', this.root).hidden = true;
    this.setSaveStatus('');
  }

  setStatus(text) {
    $('#snakeStatus', this.root).textContent = text;
  }

  bindStart(fn) { this.#bind('snakeStart', 'click', fn); }
  bindPause(fn) { this.#bind('snakePause', 'click', fn); }
  bindResume(fn) { this.#bind('snakeResume', 'click', fn); }
  bindRestart(fn) { this.#bind('snakeRestart', 'click', fn); }
  bindRetry(fn) { this.#bind('snakeRetry', 'click', fn); }

  bindDirection(fn) {
    this.root.querySelectorAll('[data-dir]').forEach(button => {
      const handler = () => fn(button.dataset.dir);
      button.addEventListener('click', handler);
      this.boundHandlers.set(button, { type: 'click', handler });
    });
  }

  unbindEvents() {
    for (const [element, { type, handler }] of this.boundHandlers) element.removeEventListener(type, handler);
    this.boundHandlers.clear();
  }

  cancelResize() {
    if (this.resizeFrame) cancelAnimationFrame(this.resizeFrame);
    this.resizeFrame = 0;
    this.resizeScheduled = false;
  }

  #bind(id, type, handler) {
    const element = $(`#${id}`, this.root);
    if (!element) return;
    const previous = this.boundHandlers.get(element);
    if (previous) element.removeEventListener(previous.type, previous.handler);
    element.addEventListener(type, handler);
    this.boundHandlers.set(element, { type, handler });
  }
}
