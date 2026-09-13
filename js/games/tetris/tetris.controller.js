export class TetrisController {
  constructor(root) {
    this.root = root;
    this.state = 'READY';
    this.score = 0;
  }

  init() {
    return this.mount();
  }

  mount() {
    if (this.state === 'DESTROYED') return this;
    this.root.innerHTML = `
      <section class="state-card state-card--empty" aria-labelledby="tetrisTitle">
        <span class="state-card__icon" aria-hidden="true">🧱</span>
        <div>
          <strong id="tetrisTitle">TETRIS está próximamente disponible.</strong>
          <p>El juego ya está registrado en la arquitectura, pero su motor todavía no está publicado.</p>
        </div>
      </section>`;
    this.state = 'READY';
    return this;
  }

  bindEvents() {}
  unbindEvents() {}
  start() { this.state = 'PLAYING'; return Promise.resolve(); }
  pause() { this.state = 'PAUSED'; }
  resume() { this.state = 'PLAYING'; }
  restart() { this.score = 0; this.state = 'READY'; return this.mount(); }
  destroy() { this.unbindEvents(); this.state = 'DESTROYED'; }
  getScore() { return this.score; }
  getState() { return { status: this.state, score: this.score }; }
}
