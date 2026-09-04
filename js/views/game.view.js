import { $, escapeHtml } from '../core/utils.js';

export function renderGameShell(game) {
  $('#gameTitle').textContent = game?.name || 'SNAKE';
  $('#gameDescription').textContent = game?.description || '';
}

export function renderUnavailable(slug) {
  $('#gameApp').innerHTML = `<div class="empty-state"><h2>Juego no disponible</h2><p>No se encontró el juego <strong>${escapeHtml(slug)}</strong> o está desactivado.</p><a class="button button--primary" href="../dashboard.html">Volver al catálogo</a></div>`;
}

