'use strict';
const test = require('node:test');
const assert = require('node:assert');
const c = require('../../lib/colors');

test('normalizeHex accepts #rgb and #rrggbb only', () => {
  assert.strictEqual(c.normalizeHex(' #ABC '), '#aabbcc');
  assert.strictEqual(c.normalizeHex('#1976D2'), '#1976d2');
  for (const bad of ['1976d2', '#12345', '#ggg', 'red', null, 42]) assert.strictEqual(c.normalizeHex(bad), null);
});

test('resolvePalette keeps valid unique colors, falls back to the built-in palette', () => {
  assert.deepStrictEqual(c.resolvePalette(['#FFF', 'nope', '#ffffff', '#000']), ['#ffffff', '#000000']);
  assert.strictEqual(c.resolvePalette([]), c.PALETTE);
  assert.strictEqual(c.resolvePalette(['x']), c.PALETTE);
  assert.strictEqual(c.resolvePalette(undefined), c.PALETTE);
});

test('the same folder always prefers the same palette color', () => {
  const key = 'file:///home/alex/project';
  assert.strictEqual(c.preferredFor(key), c.preferredFor(key));
  assert.ok(c.PALETTE.includes(c.preferredFor(key)));
  assert.strictEqual(c.preferredFor(''), null);
});

test('pickColor keeps the preferred color when it is free', () => {
  assert.strictEqual(c.pickColor(['#d32f2f'], '#388e3c'), '#388e3c');
});

test('pickColor gives each new window a color no open window has', () => {
  const taken = [];
  for (let i = 0; i < c.PALETTE.length; i++) taken.push(c.pickColor(taken, null));
  assert.deepStrictEqual(new Set(taken).size, c.PALETTE.length);
});

test('pickColor moves past a taken preferred color, then reuses the least used one', () => {
  assert.strictEqual(c.pickColor(['#1976d2'], '#1976d2'), '#388e3c');
  const full = [...c.PALETTE, ...c.PALETTE.filter((x) => x !== '#7b1fa2')];
  assert.strictEqual(c.pickColor(full, null), '#7b1fa2');
});

test('foregroundFor picks readable text', () => {
  assert.strictEqual(c.foregroundFor('#fbc02d'), '#000000');
  assert.strictEqual(c.foregroundFor('#1976d2'), '#ffffff');
});

test('mergeChrome adds and removes only its own keys', () => {
  const mine = { 'editor.background': '#111111' };
  const tinted = c.mergeChrome(mine, '#d32f2f');
  assert.strictEqual(tinted['editor.background'], '#111111');
  assert.strictEqual(tinted['titleBar.activeBackground'], '#d32f2f');
  assert.strictEqual(tinted['statusBar.foreground'], '#ffffff');
  assert.strictEqual(tinted['window.activeBorder'], '#d32f2f');
  assert.deepStrictEqual(Object.keys(c.chromeColors('#d32f2f')).sort(), [...c.CHROME_KEYS].sort());
  assert.deepStrictEqual(c.mergeChrome(tinted, null), mine);
  assert.deepStrictEqual(c.mergeChrome(undefined, null), {});
});
