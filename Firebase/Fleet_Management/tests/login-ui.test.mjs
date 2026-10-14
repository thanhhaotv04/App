import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

test('password controls preserve input, hide on submit and prevent native credential submission', () => {
  const password = { type: 'password', value: 'synthetic-test-value' };
  const labels = {};
  let ready;
  let click;
  let submit;
  const toggle = {
    textContent: 'Show',
    setAttribute: (name, value) => { labels[name] = value; },
    addEventListener: (_, callback) => { click = callback; },
  };
  const form = { addEventListener: (_, callback) => { submit = callback; } };
  const message = { hidden: false };
  const retry = { hidden: true, addEventListener() {} };
  runInNewContext(readFileSync(new URL('../dashboard/login-ui.js', import.meta.url), 'utf8'), {
    document: {
      addEventListener: (_, callback) => { ready = callback; },
      getElementById: (id) => ({ password, 'password-toggle': toggle, 'login-form': form,
        'auth-startup': message, 'retry-auth': retry })[id],
    },
    window: { addEventListener() {} },
    setTimeout() {}, clearTimeout() {},
  });
  ready();
  click();
  assert.equal(password.type, 'text');
  assert.equal(labels['aria-label'], 'Hide password');
  assert.equal(toggle.textContent, 'Hide');
  click();
  assert.equal(password.type, 'password');
  assert.equal(labels['aria-label'], 'Show password');
  click();
  let prevented = false;
  submit({ preventDefault: () => { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(password.type, 'password');
  assert.equal(toggle.textContent, 'Show');
  assert.equal(password.value, 'synthetic-test-value');
  assert.equal(message.hidden, false);
  assert.match(message.textContent, /unavailable/);
  assert.equal(retry.hidden, false);
});
