'use strict';
// Starts a real VS Code twice with this extension: once as an empty window (no folder) and once with a folder,
// and runs test/suite in each. Used by CI; needs a display (xvfb-run on Linux).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { runTests } = require('@vscode/test-electron');

async function main() {
  const extensionDevelopmentPath = path.resolve(__dirname, '..');
  const extensionTestsPath = path.resolve(__dirname, 'suite');
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'window-colors-folder-'));
  // A folder Peacock colored before: its leftover colors must be replaced by this window's color.
  fs.mkdirSync(path.join(folder, '.vscode'));
  fs.writeFileSync(
    path.join(folder, '.vscode', 'settings.json'),
    JSON.stringify({
      'peacock.color': '#abcdef',
      'workbench.colorCustomizations': {
        'titleBar.activeBackground': '#abcdef',
        'activityBar.activeBackground': '#abcdef',
        'statusBarItem.remoteBackground': '#abcdef',
        'editor.background': '#101010',
      },
    })
  );
  const version = process.env.VSCODE_VERSION || 'stable';
  for (const [mode, args] of [['empty', []], ['folder', [folder]]]) {
    console.log(`--- VS Code ${version}, ${mode} window ---`);
    await runTests({
      version,
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: [...args, '--disable-extensions', '--disable-workspace-trust'],
      extensionTestsEnv: { WINDOW_COLORS_MODE: mode, WINDOW_COLORS_FOLDER: folder },
    });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
