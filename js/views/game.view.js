import { $, escapeHtml } from '../core/utils.js';

export function renderGameLoading() {
  const app = $('#gameApp');
  if (app) {
    app.setAttribute('aria-busy', 'true');
    app.innerHTML = `
      <div class="state-card state-card--loading" role="status" aria-live="polite">
        <span class="spinner" aria-hidden="true"></span>
        <div><strong>Cargando juego…</strong><p>Preparando la partida.</p></div>
      </div>`;
  }
}

export function renderGameError(message, retry) {
  const app = $('#gameApp');
  if (!app) return;
  app.removeAttribute('aria-busy');
  app.innerHTML = `
    <div class="state-card state-card--error" role="alert">
      <span class="state-card__icon" aria-hidden="true">⚠</span>
      <div><strong>No pudimos cargar el juego</strong><p>${escapeHtml(message)}</p>
        <button class="button button--primary" id="gameRetryButton" type="button">Reintentar</button>
      </div>
    </div>`;
  $('#gameRetryButton')?.addEventListener('click', () => void retry(), { once: true });
}

export function renderGameShell(game) {
  const app = $('#gameApp');
  app?.removeAttribute('aria-busy');
  $('#gameTitle').textContent = game?.name || 'SNAKE';
  $('#gameDescription').textContent = game?.description || '';
}

export function renderUnavailable(slug) {
  const app = $('#gameApp');
  app?.removeAttribute('aria-busy');
  if (app) app.innerHTML = `<div class="state-card state-card--empty"><span class="state-card__icon" aria-hidden="true">🎮</span><div><h2>Juego no disponible</h2><p>No se encontró el juego <strong>${escapeHtml(slug)}</strong> o está desactivado.</p><a class="button button--primary" href="../dashboard.html">Volver al catálogo</a></div></div>`;
}
