import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { validate } from '../core/session.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

async function mountIndex() {
  const user = await validate();
  if (user) location.href = 'dashboard.html';
}

mountPageLifecycle({ mount: mountIndex });
