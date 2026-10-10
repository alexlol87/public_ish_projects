'use strict';
// Gives every VS Code window its own color, including windows with no folder or workspace open.
//
// The color shows on the window border, title bar, activity bar and status bar, as Peacock does, plus a colored
// status bar item and a stripe down the left edge of every editor. VS Code reads bar colors only from settings, which
// exist per user (all windows) or per workspace. Folder windows get them in the folder's settings. An empty window
// has no workspace settings, so while it has focus its color is written to the user settings; folder windows are not
// affected because their workspace colors win.

const vscode = require('vscode');
const crypto = require('crypto');
const path = require('path');
const colors = require('./lib/colors');
const registry = require('./lib/registry');

const COLOR_KEY = 'windowColors.color'; // workspaceState: survives reloads of this folder or empty window
const PEACOCK_ID = 'johnpapa.vscode-peacock';

const windowId = crypto.randomUUID();
let registryFile;
let context;
let color;
let statusItem;
let stripe; // TextEditorDecorationType, recreated when the color changes
const lineCounts = new WeakMap(); // editor -> line count the stripe was drawn for

function settings() {
  return vscode.workspace.getConfiguration('windowColors');
}

function palette() {
  return colors.resolvePalette(settings().get('palette'));
}

function folderKey() {
  const folders = vscode.workspace.workspaceFolders || [];
  const file = vscode.workspace.workspaceFile;
  if (file && file.scheme !== 'untitled') return file.toString();
  return folders.map((f) => f.uri.toString()).sort().join('|');
}

async function activate(ctx) {
  context = ctx;
  registryFile = path.join(ctx.globalStorageUri.fsPath, 'windows.json');

  statusItem = vscode.window.createStatusBarItem('windowColors.status', vscode.StatusBarAlignment.Left, 1000);
  statusItem.name = 'Window Color';
  statusItem.command = 'windowColors.pick';
  ctx.subscriptions.push(
    statusItem,
    vscode.commands.registerCommand('windowColors.pick', pick),
    vscode.window.onDidChangeVisibleTextEditors(drawStripes),
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (vscode.window.visibleTextEditors.some((ed) => ed.document === e.document)) drawStripes();
    }),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('windowColors')) apply();
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(() => setColor(undefined, false)),
    vscode.window.onDidChangeWindowState((state) => {
      if (state.focused) tintEmpty();
    }),
    { dispose: () => stripe && stripe.dispose() }
  );

  await setColor(undefined, false);
  warnAboutPeacock();
  return { getColor: () => color, setColor: (hex) => setColor(hex, true), statusColor: () => statusItem.color };
}

/** Claims a color (the given one, else the saved one, else a free one) and shows it. */
async function setColor(hex, force) {
  const saved = colors.normalizeHex(context.workspaceState.get(COLOR_KEY));
  const preferred = colors.normalizeHex(hex) || saved || colors.preferredFor(folderKey(), palette());
  try {
    color = await registry.claim(registryFile, { id: windowId, preferred, palette: palette(), force });
  } catch {
    color = preferred || palette()[0]; // storage unwritable: still color this window
  }
  if (force || !saved) await context.workspaceState.update(COLOR_KEY, color);
  await apply();
  return color;
}

async function apply() {
  const name = vscode.workspace.name || 'No folder';
  statusItem.text = `$(circle-filled) ${name}`;
  // On a status bar already in this color, the item takes the bar's text color (white, or black on light colors).
  const tinted = vscode.workspace.workspaceFolders
    ? settings().get('tintFolderWindows', true)
    : settings().get('tintEmptyWindows', true);
  statusItem.color = tinted ? undefined : color;
  statusItem.tooltip = `This window's color: ${color}. Click to change it.`;
  statusItem.show();

  if (stripe) stripe.dispose();
  stripe = undefined;
  const width = settings().get('stripeWidth', 4);
  if (width > 0) {
    stripe = vscode.window.createTextEditorDecorationType({
      isWholeLine: true,
      borderColor: color,
      borderStyle: 'solid',
      borderWidth: `0 0 0 ${width}px`,
      overviewRulerColor: color,
      overviewRulerLane: vscode.OverviewRulerLane.Full,
    });
  }
  drawStripes(true);
  await tintFolder();
  await tintEmpty();
}

function drawStripes(redraw) {
  if (!stripe) return;
  for (const editor of vscode.window.visibleTextEditors) {
    const lines = editor.document.lineCount;
    if (redraw !== true && lineCounts.get(editor) === lines) continue;
    lineCounts.set(editor, lines);
    editor.setDecorations(stripe, [new vscode.Range(0, 0, lines - 1, 0)]);
  }
}

/** Writes or removes the title/activity/status bar colors in this folder's settings. */
async function tintFolder() {
  if (!vscode.workspace.workspaceFolders) return;
  const config = vscode.workspace.getConfiguration();
  const current = (config.inspect('workbench.colorCustomizations') || {}).workspaceValue;
  const tinted = current && colors.CHROME_KEYS.some((key) => key in current);
  const want = settings().get('tintFolderWindows', true);
  if (!want && !tinted) return; // never create a settings file just to say "no tint"
  const next = colors.mergeChrome(current, want ? color : null);
  if (JSON.stringify(next) === JSON.stringify(current || {})) return;
  await config.update(
    'workbench.colorCustomizations',
    Object.keys(next).length ? next : undefined,
    vscode.ConfigurationTarget.Workspace
  );
}

/** In a window without a folder that has focus, writes or removes the bar colors in the user settings. */
async function tintEmpty() {
  if (vscode.workspace.workspaceFolders || !vscode.window.state.focused) return;
  const config = vscode.workspace.getConfiguration();
  const current = (config.inspect('workbench.colorCustomizations') || {}).globalValue;
  const want = settings().get('tintEmptyWindows', true);
  const next = colors.mergeChrome(current, want ? color : null);
  if (JSON.stringify(next) === JSON.stringify(current || {})) return;
  await config.update(
    'workbench.colorCustomizations',
    Object.keys(next).length ? next : undefined,
    vscode.ConfigurationTarget.Global
  );
}

/** Peacock writes the same colors into folder settings, so the two would overwrite each other. Said once. */
function warnAboutPeacock() {
  if (!vscode.extensions.getExtension(PEACOCK_ID) || context.globalState.get('peacockWarned')) return;
  context.globalState.update('peacockWarned', true);
  vscode.window.showWarningMessage(
    'Window Colors and Peacock both color the title, activity and status bars. Disable Peacock so the bars keep the color Window Colors picks.'
  );
}

async function pick() {
  const items = palette().map((hex) => ({
    label: hex === color ? `$(check) ${hex}` : hex,
    hex,
    iconPath: swatch(hex),
  }));
  items.push({ label: '$(edit) Custom color…', custom: true });
  const choice = await vscode.window.showQuickPick(items, { title: "This window's color" });
  if (!choice) return;
  let hex = choice.hex;
  if (choice.custom) {
    hex = await vscode.window.showInputBox({
      title: 'Hex color, like #3366ff',
      value: color,
      validateInput: (v) => (colors.isHexColor(v) ? null : 'Use #rgb or #rrggbb'),
    });
  }
  if (hex) await setColor(hex, true);
}

/** A tiny SVG square of `hex`, used as the quick pick icon. */
function swatch(hex) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" rx="3" fill="${hex}"/></svg>`;
  return vscode.Uri.parse('data:image/svg+xml;base64,' + Buffer.from(svg).toString('base64'));
}

function deactivate() {
  if (registryFile) registry.release(registryFile, windowId);
}

module.exports = { activate, deactivate };
