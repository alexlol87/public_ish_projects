'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { keyFromUrl, group, describe } = require('../lib/tree');

test('keyFromUrl matches mem.py for ssh, https and Azure DevOps', () => {
  assert.strictEqual(keyFromUrl('git@github.com:owner/repo.git'), 'owner/repo');
  assert.strictEqual(keyFromUrl('https://github.com/owner/repo/'), 'owner/repo');
  assert.strictEqual(keyFromUrl('https://dev.azure.com/org/project/_git/repo'), 'project/repo');
  assert.strictEqual(keyFromUrl(''), null);
});

test('group puts Global first, open repositories next, keeps memory order', () => {
  const m = (id, repo) => ({ id, repo });
  const groups = group([m(1, 'z/other'), m(2, null), m(3, 'a/open'), m(4, 'b/rest'), m(5, null)], ['a/open']);
  assert.deepStrictEqual(groups.map((g) => g.label), ['Global', 'a/open', 'b/rest', 'z/other']);
  assert.deepStrictEqual(groups[0].memories.map((x) => x.id), [2, 5]);
});

test('describe shows expiry only when set', () => {
  assert.strictEqual(describe({ load: 'always', expires_at: null }), 'always');
  assert.strictEqual(describe({ load: 'on_demand', expires_at: '2026-12-01T00:00:00Z' }), 'on_demand · expires 2026-12-01');
});
