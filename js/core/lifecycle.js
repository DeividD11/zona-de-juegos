/**
 * Lifecycle uniforme para controladores de página.
 * Cada página se monta una sola vez y se destruye en pagehide para evitar
 * inicializaciones duplicadas y liberar callbacks registrados por el controller.
 */
export class PageLifecycle {
  constructor({ mount, bindEvents = null, unbindEvents = null, destroy = null } = {}) {
    this._mount = mount;
    this._bindEvents = bindEvents;
    this._unbindEvents = unbindEvents;
    this._destroy = destroy;
    this.mounted = false;
  }

  async mount() {
    if (this.mounted) return;
    if (this._mount) await this._mount();
    if (this._bindEvents) this._bindEvents();
    this.mounted = true;
  }

  bindEvents() {
    if (this._bindEvents) this._bindEvents();
  }

  unbindEvents() {
    if (this._unbindEvents) this._unbindEvents();
  }

  destroy() {
    if (!this.mounted) return;
    this.unbindEvents();
    if (this._destroy) this._destroy();
    this.mounted = false;
  }
}

export function mountPageLifecycle(options) {
  const lifecycle = new PageLifecycle(options);
  const onPageHide = () => lifecycle.destroy();
  window.addEventListener('pagehide', onPageHide, { once: true });
  void lifecycle.mount();
  return lifecycle;
}
