import { $, escapeHtml, formatDate } from '../core/utils.js';

export function renderUser(user) {
  $('#userName').textContent = user.display_name;
  $('#userRole').textContent = user.role === 'admin' ? 'Administrador' : 'Jugador';
}

export function renderGamesLoading() {
  $('#gamesGrid').innerHTML = '<div class="state-card state-card--loading state-card--full" role="status"><span class="spinner" aria-hidden="true"></span><div><strong>Cargando juegos…</strong><p>Preparando el catálogo.</p></div></div>';
}

export function renderGamesError(retry) {
  $('#gamesGrid').innerHTML = '<div class="state-card state-card--error state-card--full" role="alert"><span class="state-card__icon" aria-hidden="true">⚠</span><div><strong>No pudimos cargar los juegos.</strong><p>Revisa tu conexión e inténtalo de nuevo.</p><button class="button button--primary" id="gamesRetry" type="button">Reintentar</button></div></div>';
  $('#gamesRetry')?.addEventListener('click', () => void retry(), { once: true });
}

export function renderScoresLoading() {
  $('#scoresBody').innerHTML = '<tr><td colspan="3" class="table-empty" aria-busy="true"><span class="spinner" aria-hidden="true"></span> Cargando puntuaciones…</td></tr>';
}

export function renderGames(games, retry = null) {
  const grid = $('#gamesGrid');
  if (!games.length) {
    grid.innerHTML = `
      <div class="state-card state-card--empty state-card--full" role="status">
        <span class="state-card__icon" aria-hidden="true">🎮</span>
        <div><strong>Aún no hay juegos disponibles.</strong><p>El catálogo está vacío por ahora. Vuelve a intentarlo más tarde.</p>
        <button class="button button--primary" id="gamesRetry" type="button">Reintentar</button></div>
      </div>`;
    if (retry) $('#gamesRetry')?.addEventListener('click', () => void retry(), { once: true });
    return;
  }

  const statusMeta = {
    available: { label: 'Disponible', icon: '🟢', className: 'status-badge--available' },
    upcoming: { label: 'Próximamente', icon: '🟡', className: 'status-badge--upcoming' },
    disabled: { label: 'Desactivado', icon: '🔴', className: 'status-badge--disabled' }
  };

  grid.innerHTML = games.map(game => {
    const status = game.is_active ? (game.release_status === 'upcoming' ? 'upcoming' : 'available') : 'disabled';
    const meta = statusMeta[status];
    const best = Number(game.best_score) || 0;
    const action = status === 'available'
      ? `<a class="button button--primary" href="pages/game.html?game=${encodeURIComponent(game.slug)}">Jugar</a>`
      : `<button class="button button--ghost" type="button" disabled>${meta.label}</button>`;

    return `
      <article class="game-card game-card--${status}">
        <div class="game-card__icon" aria-hidden="true">${escapeHtml(game.icon)}</div>
        <div class="game-card__body">
          <div class="game-card__topline">
            <span class="status-badge ${meta.className}">${meta.icon} ${meta.label}</span>
            <span class="game-card__version">v${escapeHtml(game.current_version || '1.0.0')}</span>
          </div>
          <h3>${escapeHtml(game.name)}</h3>
          <p>${escapeHtml(game.description)}</p>
          <div class="game-card__meta"><span><strong>Mejor:</strong> ${best}</span></div>
          ${action}
        </div>
      </article>`;
  }).join('');
}

export function renderScores(scores) {
  const tbody = $('#scoresBody');
  tbody.innerHTML = scores.length ? scores.map(score => `
    <tr><td>${escapeHtml(score.game_name)}</td><td><strong>${score.best_score}</strong></td><td>${formatDate(score.last_played)}</td></tr>
  `).join('') : '<tr><td colspan="3" class="table-empty"><div class="empty-state"><span class="state-card__icon" aria-hidden="true">🏆</span><h3>Aún no tienes partidas.</h3><p>Juega tu primera partida de SNAKE y aquí aparecerá tu historial.</p><a class="button button--small button--ghost" href="pages/game.html?game=snake">Jugar SNAKE</a></div></td></tr>';
}
