'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const registry = require('../../lib/registry');

function tempFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'window-colors-')), 'windows.json');
}

const alive = (pid) => pid !== 999;

test('windows opening at the same time get different colors', async () => {
  const file = tempFile();
  const got = await Promise.all(
    Array.from({ length: 6 }, (_, i) => registry.claim(file, { id: `w${i}`, pid: i + 1, preferred: null, alive }))
  );
  assert.strictEqual(new Set(got).size, 6);
  assert.strictEqual(registry.read(file).length, 6);
});

test('a closed window frees its color', async () => {
  const file = tempFile();
  const first = await registry.claim(file, { id: 'dead', pid: 999, preferred: '#d32f2f', alive });
  const second = await registry.claim(file, { id: 'new', pid: 2, preferred: '#d32f2f', alive });
  assert.strictEqual(first, '#d32f2f');
  assert.strictEqual(second, '#d32f2f');
  assert.deepStrictEqual(registry.read(file).map((e) => e.id), ['new']);
});

test('a chosen color is kept even when another window has it', async () => {
  const file = tempFile();
  await registry.claim(file, { id: 'a', pid: 1, preferred: '#d32f2f', alive });
  assert.strictEqual(await registry.claim(file, { id: 'b', pid: 2, preferred: '#d32f2f', alive }), '#1976d2');
  assert.strictEqual(await registry.claim(file, { id: 'b', pid: 2, preferred: '#d32f2f', force: true, alive }), '#d32f2f');
  assert.strictEqual(registry.read(file).length, 2);
});

test('release removes the window; a broken file reads as empty', async () => {
  const file = tempFile();
  await registry.claim(file, { id: 'a', pid: 1, preferred: null, alive });
  registry.release(file, 'a', alive);
  assert.deepStrictEqual(registry.read(file), []);
  fs.writeFileSync(file, '{not json');
  assert.deepStrictEqual(registry.read(file), []);
});

test('a lock left by a crashed window does not block forever', async () => {
  const file = tempFile();
  const lock = `${file}.lock`;
  fs.mkdirSync(lock);
  const old = new Date(Date.now() - 10000);
  fs.utimesSync(lock, old, old);
  assert.ok(await registry.claim(file, { id: 'a', pid: 1, preferred: null, alive }));
  assert.ok(!fs.existsSync(lock));
});

test('isAlive knows this process', () => {
  assert.ok(registry.isAlive(process.pid));
});
