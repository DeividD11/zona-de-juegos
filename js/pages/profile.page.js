import { enforceHttps } from '../core/transport-security.js';
enforceHttps();
import { initProfile } from '../controllers/profile.controller.js';
import { mountPageLifecycle } from '../core/lifecycle.js';

mountPageLifecycle({ mount: initProfile });
