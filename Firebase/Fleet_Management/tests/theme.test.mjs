import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../dashboard/theme.js', import.meta.url), 'utf8');
const key = 'navride-fleet-theme';

function page(saved, blocked = false) {
  const storage = new Map(saved === undefined ? [] : [[key, saved]]);
  const root = { dataset: {} };
  const meta = {};
  const attributes = {};
  const listeners = {};
  let ready;
  let click;
  let mounted = false;
  const button = {
    setAttribute: (name, value) => { attributes[name] = value; },
    addEventListener: (_, handler) => { click = handler; },
  };
  runInNewContext(source, {
    document: {
      documentElement: root,
      querySelector: () => meta,
      getElementById: () => mounted ? button : null,
      addEventListener: (_, handler) => { ready = handler; },
    },
    getComputedStyle: () => ({ getPropertyValue: () => root.dataset.theme === 'light' ? '#f5f6f7' : '#16191f' }),
    localStorage: {
      getItem: (name) => { if (blocked) throw new Error('Storage denied'); return storage.get(name); },
      setItem: (name, value) => { if (blocked) throw new Error('Storage denied'); storage.set(name, value); },
    },
    window: { addEventListener: (name, handler) => { listeners[name] = handler; } },
  });
  return {
    root, meta, attributes, storage,
    ready: () => { mounted = true; ready(); },
    click: () => click(),
    storageEvent: (event) => listeners.storage(event),
  };
}

test('dark is the default before page content and Firebase are initialized', () => {
  const current = page();
  assert.equal(current.root.dataset.theme, 'dark');
  assert.equal(current.meta.content, '#16191f');
  current.ready();
  assert.equal(current.attributes['aria-checked'], 'true');
});

test('saved light mode is applied before content and survives a page reload', () => {
  const current = page();
  current.ready();
  current.click();
  assert.equal(current.attributes['aria-checked'], 'false');
  assert.equal(current.meta.content, '#f5f6f7');
  const reloaded = page(current.storage.get(key));
  assert.equal(reloaded.root.dataset.theme, 'light');
  reloaded.ready();
  reloaded.click();
  assert.equal(reloaded.storage.get(key), 'dark');
  assert.equal(reloaded.attributes['aria-checked'], 'true');
});

test('blocked browser storage does not prevent switching themes', () => {
  const current = page(undefined, true);
  current.ready();
  current.click();
  assert.equal(current.root.dataset.theme, 'light');
  current.click();
  assert.equal(current.root.dataset.theme, 'dark');
});

test('invalid preferences fall back to dark without accepting arbitrary values', () => {
  assert.equal(page('system').root.dataset.theme, 'dark');
  assert.equal(page('<script>').root.dataset.theme, 'dark');
});

test('theme changes in other tabs sync without reading or changing fleet data', () => {
  const current = page();
  current.ready();
  current.storageEvent({ key: 'unrelated', newValue: 'light' });
  assert.equal(current.root.dataset.theme, 'dark');
  current.storageEvent({ key, newValue: 'light' });
  assert.equal(current.attributes['aria-checked'], 'false');
  current.storageEvent({ key, newValue: null });
  assert.equal(current.root.dataset.theme, 'dark');
  current.storageEvent({ key, newValue: 'light' });
  current.storageEvent({ key: null, newValue: null });
  assert.equal(current.root.dataset.theme, 'dark');
});
