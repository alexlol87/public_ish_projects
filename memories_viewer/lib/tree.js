'use strict';
// Pure helpers for the Memories view: no vscode import, so the unit tests run under plain node.

// Same rule as key_from_url in local_memory_sqlite/mem.py: the last two path parts of the origin URL.
function keyFromUrl(url) {
  const parts = url.trim().replace(/\/+$/, '').replace(/\.git$/, '').split(/[/:]/).filter((p) => p && p !== '_git');
  return parts.length >= 2 ? parts.slice(-2).join('/') : null;
}

// Memories (already in the order to show) -> [{label, repo, memories}]: Global first, then the open repositories,
// then the rest by name. Empty groups are left out.
function group(memories, openRepos) {
  const byRepo = new Map();
  for (const m of memories) {
    if (!byRepo.has(m.repo)) byRepo.set(m.repo, []);
    byRepo.get(m.repo).push(m);
  }
  const rank = (repo) => (repo === null ? 0 : openRepos.includes(repo) ? 1 : 2);
  return [...byRepo.keys()]
    .sort((a, b) => rank(a) - rank(b) || String(a).localeCompare(String(b)))
    .map((repo) => ({ label: repo === null ? 'Global' : repo, repo, memories: byRepo.get(repo) }));
}

function describe(m) {
  return m.expires_at ? `${m.load} · expires ${m.expires_at.slice(0, 10)}` : m.load;
}

module.exports = { keyFromUrl, group, describe };
