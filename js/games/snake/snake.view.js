import { $ } from '../../core/utils.js';

export class SnakeView {
  constructor(root) {
    this.root = root;
    root.innerHTML = `
      <div class="snake-toolbar">
        <div><span>Puntuación</span><strong id="snakeScore">0</strong></div>
        <div><span>Mejor</span><strong id="snakeBest">0</strong></div>
        <div><button class="button button--small" id="snakeStart">Iniciar</button></div>
      </div>
      <div class="snake-board-wrap"><canvas id="snakeCanvas" class="snake-canvas" aria-label="Tablero del juego SNAKE"></canvas></div>
      <div class="snake-status" id="snakeStatus">Pulsa “Iniciar” o una flecha para comenzar.</div>
      <div class="snake-controls" role="group" aria-label="Controles táctiles">
        <button type="button" data-dir="up" aria-label="Mover arriba">↑</button>
        <button type="button" data-dir="left" aria-label="Mover izquierda">←</button>
        <button type="button" data-dir="down" aria-label="Mover abajo">↓</button>
        <button type="button" data-dir="right" aria-label="Mover derecha">→</button>
      </div>
    `;
    this.canvas = $('#snakeCanvas', root);
    this.ctx = this.canvas.getContext('2d');
  }

  resize(size) {
    const max = Math.min(this.root.clientWidth - 8, 620);
    const px = Math.max(160, max);
    const dpr = window.devicePixelRatio || 1;
    this.canvas.style.width = `${px}px`;
    this.canvas.style.height = `${px}px`;
    this.canvas.width = Math.floor(px * dpr);
    this.canvas.height = Math.floor(px * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.render(this.lastState, size);
  }

  render(state, size = 20) {
    if (!state) return;
    this.lastState = state;
    const px = parseFloat(getComputedStyle(this.canvas).width) || 400;
    const cell = px / size;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, px, px);
    ctx.fillStyle = '#0b1220'; ctx.fillRect(0, 0, px, px);
    ctx.strokeStyle = 'rgba(255,255,255,.05)'; ctx.lineWidth = 1;
    for (let i = 0; i <= size; i++) { const p = i * cell; ctx.beginPath(); ctx.moveTo(p,0); ctx.lineTo(p,px); ctx.stroke(); ctx.beginPath(); ctx.moveTo(0,p); ctx.lineTo(px,p); ctx.stroke(); }

    if (state.food) { ctx.fillStyle = '#ef4444'; ctx.beginPath(); ctx.arc((state.food.x+.5)*cell, (state.food.y+.5)*cell, cell*.32, 0, Math.PI*2); ctx.fill(); }
    state.snake.forEach((part, index) => {
      ctx.fillStyle = index === 0 ? '#60a5fa' : '#3b82f6';
      const pad = cell*.11; ctx.fillRect(part.x*cell+pad, part.y*cell+pad, cell-pad*2, cell-pad*2);
    });

    $('#snakeScore', this.root).textContent = String(state.score);
    $('#snakeStatus', this.root).textContent = state.gameOver ? 'Game Over. Pulsa “Iniciar” para jugar otra vez.' : state.running ? '¡En juego! Usa el teclado o los controles táctiles.' : 'Pulsa “Iniciar” o una flecha para comenzar.';
  }

  setStatus(text) {
    $('#snakeStatus', this.root).textContent = text;
  }

  bindStart(fn) { $('#snakeStart', this.root).addEventListener('click', fn); }
  bindDirection(fn) { this.root.querySelectorAll('[data-dir]').forEach(button => button.addEventListener('click', () => fn(button.dataset.dir))); }
}
