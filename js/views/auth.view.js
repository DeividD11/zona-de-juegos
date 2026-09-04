import { $ } from '../core/utils.js';

export function bindAuth(formSelector, submitHandler) {
  const form = $(formSelector);
  form?.addEventListener('submit', event => {
    event.preventDefault();
    submitHandler(new FormData(form));
  });
}
