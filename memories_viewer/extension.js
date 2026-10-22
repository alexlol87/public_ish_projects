'use strict';
// Read-only sidebar for local_memory_sqlite: lists memories grouped by scope, opens one in an editor tab.
// All data comes from the mem.py JSON CLI, so expiry cleanup and the database path stay its business.

const vscode = require('vscode');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { keyFromUrl, group, describe } = require('./lib/tree');

const MEM = path.join(os.homedir(), '.local_memory_sqlite', 'mem.py');
const SCHEME = 'memory';

function run(cmd, args) {
  return new Promise((resolve) => {
    execFile(cmd, args, { cwd: os.homedir(), timeout: 10000, maxBuffer: 64 * 1024 * 1024 }, (err, stdout) =>
      resolve({ err, stdout: String(stdout || '').trim() }));
  });
}

async function mem(args) {
  const { err, stdout } = await run('python3', [MEM, ...args]);
  let out;
  try {
    out = JSON.parse(stdout);
  } catch {
    throw new Error(err ? `${MEM}: ${err.message}` : `${MEM} printed no JSON`);
  }
  if (out.error) throw new Error(out.error);
  return out.memories;
}

// Mirrors repo_key in mem.py for each open folder, so their groups come first.
async function openRepos() {
  const keys = [];
  for (const f of vscode.workspace.workspaceFolders || []) {
    const dir = f.uri.fsPath;
    const origin = await run('git', ['-C', dir, 'remote', 'get-url', 'origin']);
    const top = await run('git', ['-C', dir, 'rev-parse', '--show-toplevel']);
    keys.push((!origin.err && keyFromUrl(origin.stdout)) || 'local/' + path.basename(top.err ? dir : top.stdout));
  }
  return keys;
}

class Memories {
  constructor() {
    this.changed = new vscode.EventEmitter();
    this.onDidChangeTreeData = this.changed.event;
    this.byId = new Map();
    this.docsChanged = new vscode.EventEmitter();
    this.onDidChange = this.docsChanged.event; // for open memory tabs
    this.query = '';
    this.open = []; // repository keys of the open folders
    this.groups = null;
  }

  async refresh() {
    this.groups = null;
    this.changed.fire();
    await this.getChildren();
    for (const doc of vscode.workspace.textDocuments) if (doc.uri.scheme === SCHEME) this.docsChanged.fire(doc.uri);
  }

  async load() {
    try {
      const memories = await mem(this.query ? ['search', ...this.query.split(/\s+/), '--all-repos', '--limit', '500']
        : ['list', '--all-repos']);
      this.byId = new Map(memories.map((m) => [m.id, m]));
      this.open = await openRepos();
      return group(memories, this.open);
    } catch (e) {
      return [{ error: e.message }];
    }
  }

  async getChildren(node) {
    if (node) return node.memories;
    this.groups = this.groups || this.load();
    return this.groups;
  }

  getTreeItem(node) {
    if (node.error) {
      const item = new vscode.TreeItem(node.error);
      item.iconPath = new vscode.ThemeIcon('error');
      return item;
    }
    if (node.memories) {
      const item = new vscode.TreeItem(`${node.label} (${node.memories.length})`, this.query || node.repo === null
        || this.open.includes(node.repo) ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.Collapsed);
      item.iconPath = new vscode.ThemeIcon(node.repo === null ? 'globe' : 'repo');
      return item;
    }
    const item = new vscode.TreeItem(node.title);
    item.description = describe(node);
    item.tooltip = node.content.length > 500 ? node.content.slice(0, 500) + '…' : node.content;
    item.iconPath = new vscode.ThemeIcon(node.load === 'always' ? 'pinned' : 'note');
    item.command = { command: 'memories.open', title: 'Open Memory', arguments: [node] };
    return item;
  }

  // Read-only documents: memory:/<id>/<title>.md
  provideTextDocumentContent(uri) {
    const m = this.byId.get(Number(uri.path.split('/')[1]));
    return m ? m.content : '(this memory no longer exists)';
  }
}

function activate(ctx) {
  const memories = new Memories();
  const view = vscode.window.createTreeView('memories.list', { treeDataProvider: memories });

  const refresh = () => memories.refresh();
  const search = async (query) => {
    memories.query = query;
    view.message = query ? `Search: ${query}` : undefined;
    await vscode.commands.executeCommand('setContext', 'memories.searching', !!query);
    refresh();
  };

  ctx.subscriptions.push(
    view,
    vscode.workspace.registerTextDocumentContentProvider(SCHEME, memories),
    view.onDidChangeVisibility((e) => e.visible && refresh()),
    vscode.commands.registerCommand('memories.refresh', refresh),
    vscode.commands.registerCommand('memories.clearSearch', () => search('')),
    vscode.commands.registerCommand('memories.search', async () => {
      const query = await vscode.window.showInputBox({ prompt: 'Words in the title or content', value: memories.query });
      if (query !== undefined) search(query.trim());
    }),
    vscode.commands.registerCommand('memories.open', async (m) => {
      const uri = vscode.Uri.from({ scheme: SCHEME, path: `/${m.id}/${m.title.replace(/[\\/]/g, '-')}.md` });
      await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(uri), { preview: true });
    }),
  );
  return memories; // for the integration test
}

module.exports = { activate };
