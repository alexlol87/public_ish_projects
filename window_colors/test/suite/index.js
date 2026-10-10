'use strict';
// Runs inside VS Code's extension host (see test/runTest.js).
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vscode = require('vscode');
const { PALETTE } = require('../../lib/colors');

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The extension reacts to a settings change asynchronously, so poll instead of waiting a fixed time.
async function waitFor(read, expected, ms = 5000) {
  const until = Date.now() + ms;
  while (read() !== expected && Date.now() < until) await wait(50);
  return read();
}

async function api() {
  const ext = vscode.extensions.getExtension('alexlol87.window-colors');
  assert.ok(ext, 'extension is installed');
  return ext.activate();
}

async function emptyWindow() {
  assert.strictEqual(vscode.workspace.workspaceFolders, undefined, 'no folder is open');
  const colors = await api();
  assert.ok(PALETTE.includes(colors.getColor()), `got a palette color, not ${colors.getColor()}`);

  const commands = await vscode.commands.getCommands(true);
  assert.ok(commands.includes('windowColors.pick'));

  // The stripe is drawn on editors in an empty window too.
  const doc = await vscode.workspace.openTextDocument({ content: 'one\ntwo\nthree' });
  await vscode.window.showTextDocument(doc);
  await wait(200);

  assert.strictEqual(await colors.setColor('#123ABC'), '#123abc');
  assert.strictEqual(colors.getColor(), '#123abc');

  // The bars are colored through the user settings, but only while this window has focus.
  const user = () => vscode.workspace.getConfiguration().inspect('workbench.colorCustomizations').globalValue || {};
  const border = () => user()['window.activeBorder'];
  if (vscode.window.state.focused) {
    assert.strictEqual(await waitFor(border, '#123abc'), '#123abc');
    assert.strictEqual(user()['titleBar.activeBackground'], '#123abc');
  }
  await vscode.workspace.getConfiguration('windowColors').update('tintEmptyWindows', false, vscode.ConfigurationTarget.Global);
  assert.strictEqual(await waitFor(border, undefined), undefined, 'turning it off removes the tint');
  assert.strictEqual(user()['titleBar.activeBackground'], undefined);
}

async function folderWindow() {
  const folder = process.env.WINDOW_COLORS_FOLDER;
  assert.strictEqual(vscode.workspace.workspaceFolders.length, 1);
  const colors = await api();
  const settingsFile = path.join(folder, '.vscode', 'settings.json');

  // Tinted by default, like Peacock, replacing the colors Peacock left in this folder (see test/runTest.js).
  const custom = () => vscode.workspace.getConfiguration().inspect('workbench.colorCustomizations').workspaceValue || {};
  const titleBar = () => custom()['titleBar.activeBackground'];
  assert.strictEqual(await waitFor(titleBar, colors.getColor()), colors.getColor());
  assert.strictEqual(custom()['window.activeBorder'], colors.getColor());
  assert.strictEqual(custom()['activityBar.activeBackground'], colors.getColor());
  assert.strictEqual(custom()['statusBarItem.remoteBackground'], colors.getColor());
  assert.strictEqual(custom()['editor.background'], '#101010', 'other colors are kept');
  assert.ok(fs.existsSync(settingsFile));

  assert.strictEqual(colors.statusColor(), undefined, 'the ● takes the tinted bar\'s text color');

  await colors.setColor('#fbc02d');
  assert.strictEqual(custom()['titleBar.activeBackground'], '#fbc02d');
  assert.strictEqual(custom()['titleBar.activeForeground'], '#000000');

  await vscode.workspace.getConfiguration('windowColors').update('tintFolderWindows', false, vscode.ConfigurationTarget.Workspace);
  assert.strictEqual(await waitFor(titleBar, undefined), undefined, 'turning it off removes the tint');
  assert.strictEqual(colors.statusColor(), '#fbc02d', 'without the tint the ● shows the color itself');
}

async function run() {
  const mode = process.env.WINDOW_COLORS_MODE;
  await (mode === 'folder' ? folderWindow() : emptyWindow());
  console.log(`window-colors ${mode} window: ok`);
}

module.exports = { run };
