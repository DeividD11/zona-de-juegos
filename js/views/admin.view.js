import { $, escapeHtml, formatDate } from '../core/utils.js';

function renderPager(id, state) {
  const page = Number(state?.page) || 1;
  const pageCount = Math.max(1, Number(state?.page_count) || 1);
  const total = Number(state?.total) || 0;
  const first = total === 0 ? 0 : (page - 1) * Number(state.limit) + 1;
  const last = Math.min(total, page * Number(state.limit));
  return `<nav class="pagination" aria-label="Controles de paginación">
    <span class="pagination__info">${first}–${last} de ${total}</span>
    <div class="pagination__buttons">
      <button class="button button--small button--ghost" data-pager="${id}" data-page="${page - 1}" ${page <= 1 ? 'disabled' : ''}>Anterior</button>
      <span aria-current="page">Página ${page} de ${pageCount}</span>
      <button class="button button--small button--ghost" data-pager="${id}" data-page="${page + 1}" ${page >= pageCount ? 'disabled' : ''}>Siguiente</button>
    </div>
  </nav>`;
}

export function renderAdminLoading() {
  $('#adminUsersBody').innerHTML = '<tr><td colspan="5" class="table-empty">Cargando usuarios…</td></tr>';
  $('#adminGamesBody').innerHTML = '<tr><td colspan="5" class="table-empty">Cargando juegos…</td></tr>';
  $('#adminScoresBody').innerHTML = '<tr><td colspan="5" class="table-empty">Cargando puntuaciones…</td></tr>';
  $('#adminSessionsBody').innerHTML = '<tr><td colspan="6" class="table-empty">Cargando sesiones…</td></tr>';
  $('#adminAuditBody').innerHTML = '<tr><td colspan="6" class="table-empty">Cargando auditoría…</td></tr>';
}

export function renderUsers(result, actor) {
  const users = result?.data || [];
  $('#adminUsersBody').innerHTML = users.length ? users.map(user => `
    <tr>
      <td><strong>${escapeHtml(user.display_name)}</strong><br><small>${escapeHtml(user.email)}</small></td>
      <td><span class="badge ${user.role === 'admin' ? 'badge--admin' : ''}">${user.role === 'admin' ? 'Administrador' : 'Usuario'}</span></td>
      <td><span class="status-dot ${user.is_active ? 'status-dot--on' : 'status-dot--off'}">${user.is_active ? 'Activo' : 'Inactivo'}</span></td>
      <td>${formatDate(user.created_at)}</td>
      <td>${user.id === actor.id ? '<span class="muted">Tu cuenta</span>' : `<select class="role-select" data-user-id="${user.id}"><option value="user" ${user.role === 'user' ? 'selected' : ''}>Usuario</option><option value="admin" ${user.role === 'admin' ? 'selected' : ''}>Administrador</option></select>`}</td>
    </tr>
  `).join('') : '<tr><td colspan="5" class="table-empty">No hay usuarios.</td></tr>';
  $('#adminUsersPager').innerHTML = renderPager('users', result);
}

export function renderGames(games) {
  $('#adminGamesBody').innerHTML = games.length ? games.map(game => `
    <tr>
      <td><strong>${escapeHtml(game.icon)} ${escapeHtml(game.name)}</strong><br><small>${escapeHtml(game.slug)}</small></td>
      <td>${escapeHtml(game.description)}</td>
      <td>${escapeHtml(game.current_version || '1.0.0')}</td>
      <td><span class="status-dot ${game.is_active ? 'status-dot--on' : 'status-dot--off'}">${game.is_active ? 'Activo' : 'Desactivado'}</span></td>
      <td><button class="button button--small ${game.is_active ? 'button--ghost' : 'button--primary'} game-toggle" data-game-id="${game.id}" data-next-active="${!game.is_active}">${game.is_active ? 'Desactivar' : 'Activar'}</button></td>
    </tr>
  `).join('') : '<tr><td colspan="5" class="table-empty">No hay juegos.</td></tr>';
}

export function renderScores(result) {
  const rows = result?.data || [];
  $('#adminScoresBody').innerHTML = rows.length ? rows.map(row => `
    <tr><td>${escapeHtml(row.display_name)}<br><small>${escapeHtml(row.email)}</small></td><td>${escapeHtml(row.game_name)}</td><td><strong>${row.score}</strong></td><td>${formatDate(row.created_at)}</td><td><small>${escapeHtml(row.slug)}</small></td></tr>
  `).join('') : '<tr><td colspan="5" class="table-empty">No hay puntuaciones.</td></tr>';
  $('#adminScoresPager').innerHTML = renderPager('scores', result);
}

export function renderSessions(result) {
  const rows = result?.data || [];
  $('#adminSessionsBody').innerHTML = rows.length ? rows.map(row => {
    const status = row.revoked_at ? 'Revocada' : (new Date(row.expires_at) <= new Date() ? 'Expirada' : 'Activa');
    return `<tr><td>${escapeHtml(row.display_name)}<br><small>${escapeHtml(row.email)}</small></td><td>${formatDate(row.created_at)}</td><td>${formatDate(row.last_seen_at)}</td><td>${formatDate(row.expires_at)}</td><td>${row.revoked_at ? formatDate(row.revoked_at) : '—'}</td><td><span class="status-dot ${status === 'Activa' ? 'status-dot--on' : 'status-dot--off'}">${status}</span></td></tr>`;
  }).join('') : '<tr><td colspan="6" class="table-empty">No hay sesiones.</td></tr>';
  $('#adminSessionsPager').innerHTML = renderPager('sessions', result);
}

export function renderAudit(result) {
  const rows = result?.data || [];
  $('#adminAuditBody').innerHTML = rows.length ? rows.map(row => `
    <tr><td>${escapeHtml(row.admin_name || 'Administrador eliminado')}</td><td>${escapeHtml(row.action)}</td><td>${escapeHtml(row.target_type)}</td><td>${escapeHtml(row.target_id || '—')}</td><td>${formatDate(row.occurred_at)}</td><td><span class="status-dot status-dot--on">${escapeHtml(row.result)}</span></td></tr>
  `).join('') : '<tr><td colspan="6" class="table-empty">No hay eventos de auditoría.</td></tr>';
  $('#adminAuditPager').innerHTML = renderPager('audit', result);
}
