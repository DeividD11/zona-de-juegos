import { $, escapeHtml, formatDate } from '../core/utils.js';

export function renderAdminLoading() {
  $('#adminUsersBody').innerHTML = '<tr><td colspan="5" class="table-empty">Cargando usuarios…</td></tr>';
  $('#adminGamesBody').innerHTML = '<tr><td colspan="4" class="table-empty">Cargando juegos…</td></tr>';
}


export function renderAdmin(data, actor) {
  $('#adminUsersBody').innerHTML = data.users.map(user => `
    <tr>
      <td><strong>${escapeHtml(user.display_name)}</strong><br><small>${escapeHtml(user.email)}</small></td>
      <td><span class="badge ${user.role === 'admin' ? 'badge--admin' : ''}">${user.role === 'admin' ? 'Administrador' : 'Usuario'}</span></td>
      <td><span class="status-dot ${user.is_active ? 'status-dot--on' : 'status-dot--off'}">${user.is_active ? 'Activo' : 'Inactivo'}</span></td>
      <td>${formatDate(user.created_at)}</td>
      <td>${user.id === actor.id ? '<span class="muted">Tu cuenta</span>' : `<select class="role-select" data-user-id="${user.id}"><option value="user" ${user.role === 'user' ? 'selected' : ''}>Usuario</option><option value="admin" ${user.role === 'admin' ? 'selected' : ''}>Administrador</option></select>`}</td>
    </tr>
  `).join('');

  $('#adminGamesBody').innerHTML = data.games.map(game => `
    <tr>
      <td><strong>${escapeHtml(game.icon)} ${escapeHtml(game.name)}</strong><br><small>${escapeHtml(game.slug)}</small></td>
      <td>${escapeHtml(game.description)}</td>
      <td><span class="status-dot ${game.is_active ? 'status-dot--on' : 'status-dot--off'}">${game.is_active ? 'Activo' : 'Desactivado'}</span></td>
      <td><button class="button button--small ${game.is_active ? 'button--ghost' : 'button--primary'} game-toggle" data-game-id="${game.id}" data-next-active="${!game.is_active}">${game.is_active ? 'Desactivar' : 'Activar'}</button></td>
    </tr>
  `).join('');
}
