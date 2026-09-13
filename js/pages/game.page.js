import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initGame, destroyGame } from '../controllers/game.controller.js';
import { logout } from '../core/session.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

document.querySelector('#logoutButton')?.addEventListener('click', async () => {
  try { await logout(); }
  finally { location.href = '../login.html'; }
});

mountPageLifecycle({ mount: initGame, destroy: destroyGame });
