export function $(selector, root = document) {
  return root.querySelector(selector);
}

export function $all(selector, root = document) {
  return [...root.querySelectorAll(selector)];
}

export function escapeHtml(value = '') {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

export function setMessage(element, text, type = 'error') {
  if (!element) return;
  element.textContent = text || '';
  element.className = `message ${text ? `message--${type}` : ''}`;
  element.hidden = !text;
}

export function setBusy(button, busy, text = 'Procesando…') {
  if (!button) return;
  if (busy) {
    button.dataset.defaultText = button.textContent;
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    button.textContent = text;
  } else {
    button.disabled = false;
    button.removeAttribute('aria-busy');
    button.textContent = button.dataset.defaultText || button.textContent;
  }
}

export function formatDate(value) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('es-CO', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}

export function getQueryParam(name) {
  return new URLSearchParams(location.search).get(name);
}
