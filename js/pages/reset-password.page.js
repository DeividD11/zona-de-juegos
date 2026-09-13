import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initResetPassword } from '../controllers/recovery.controller.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

mountPageLifecycle({ mount: initResetPassword });
