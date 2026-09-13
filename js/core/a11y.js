const LIVE_ID = 'appLiveRegion';

export function announce(message, { politeness = 'polite' } = {}) {
  let region = document.getElementById(LIVE_ID);
  if (!region) {
    region = document.createElement('div');
    region.id = LIVE_ID;
    region.className = 'sr-only';
    region.setAttribute('aria-live', politeness);
    region.setAttribute('aria-atomic', 'true');
    document.body.appendChild(region);
  }
  region.setAttribute('aria-live', politeness);
  region.textContent = '';
  requestAnimationFrame(() => { region.textContent = String(message || ''); });
}

export function setFieldError(input, errorElement, message) {
  if (!input || !errorElement) return;
  const hasError = Boolean(message);
  input.setAttribute('aria-invalid', String(hasError));
  errorElement.textContent = message || '';
  errorElement.hidden = !hasError;
}
