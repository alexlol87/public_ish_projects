'use strict';
// Runs inside VS Code: see README "Test". Expects the seeded memories from test/seed.sh.
const assert = require('assert');
const vscode = require('vscode');

exports.run = async () => {
  const memories = await vscode.extensions.getExtension('alexlol87.memories-viewer').activate();
  await memories.refresh();
  const groups = await memories.getChildren();
  assert.deepStrictEqual(groups.map((g) => g.label), ['Global', 'alexlol87/public_ish_projects', 'acme/payments']);
  assert.strictEqual(memories.getTreeItem(groups[0].memories[0]).description, 'on_demand · expires 2026-12-02');

  await vscode.commands.executeCommand('memories.open', groups[0].memories[1]);
  const doc = vscode.window.activeTextEditor.document;
  assert.strictEqual(doc.languageId, 'markdown');
  assert.match(doc.getText(), /^# Stdlib first/);

  memories.query = 'bruno';
  await memories.refresh();
  assert.deepStrictEqual((await memories.getChildren()).map((g) => g.label), ['acme/payments']);
  console.log('memories-viewer: integration test passed');
};
