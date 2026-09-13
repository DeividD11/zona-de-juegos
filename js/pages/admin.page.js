import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initAdmin } from '../controllers/admin.controller.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

mountPageLifecycle({ mount: initAdmin });
