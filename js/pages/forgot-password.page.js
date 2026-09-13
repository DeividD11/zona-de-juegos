import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initForgotPassword } from '../controllers/recovery.controller.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

mountPageLifecycle({ mount: initForgotPassword });
