import { $, escapeHtml, formatDate } from '../core/utils.js';

export function renderUser(user) {
  $('#userName').textContent = user.display_name;
  $('#userRole').textContent = user.role === 'admin' ? 'Administrador' : 'Jugador';
}

export function renderGamesLoading() {
  $('#gamesGrid').innerHTML = '<div class="panel loading-state" aria-busy="true">Cargando juegos…</div>';
}

export function renderScoresLoading() {
  $('#scoresBody').innerHTML = '<tr><td colspan="3" class="table-empty" aria-busy="true">Cargando puntuaciones…</td></tr>';
}

export function renderGames(games) {
  const grid = $('#gamesGrid');
  grid.innerHTML = games.length ? games.map(game => `
    <article class="game-card">
      <div class="game-card__icon" aria-hidden="true">${escapeHtml(game.icon)}</div>
      <div class="game-card__body">
        <span class="eyebrow">Juego disponible</span>
        <h3>${escapeHtml(game.name)}</h3>
        <p>${escapeHtml(game.description)}</p>
        <a class="button button--primary" href="pages/game.html?game=${encodeURIComponent(game.slug)}">Jugar ahora</a>
      </div>
    </article>
  `).join('') : '<div class="empty-state"><h3>No hay juegos activos</h3><p>Vuelve a intentarlo más tarde.</p></div>';
}

export function renderScores(scores) {
  const tbody = $('#scoresBody');
  tbody.innerHTML = scores.length ? scores.map(score => `
    <tr><td>${escapeHtml(score.game_name)}</td><td><strong>${score.best_score}</strong></td><td>${formatDate(score.last_played)}</td></tr>
  `).join('') : '<tr><td colspan="3" class="table-empty">No tienes puntuaciones todavía.</td></tr>';
}
