import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initDashboard } from '../controllers/dashboard.controller.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

mountPageLifecycle({ mount: initDashboard });
