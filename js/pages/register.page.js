import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initRegister } from '../controllers/auth.controller.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

mountPageLifecycle({ mount: initRegister });
