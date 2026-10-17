// Generates a large fictional Vault for scale testing: `node e2e/genvault.mjs [dir] [projects] [repos]`.
// Defaults (20 projects x 12 repos) give about 5,200 Notes with Links, Calls, Uses and Tags. Prints the directory.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const WORDS = "cart order payment invoice refund ledger catalog search session token user account shipping stock price discount coupon review rating report export import queue retry webhook audit email sms notification profile address tax currency".split(" ");
const VERBS = "creates reads updates deletes lists validates syncs computes caches publishes".split(" ");
const TAGS = ["payments", "auth", "perf", "security", "legacy", "team/core", "team/growth", "team/payments", "infra/db", "infra/queue"];

/** Small deterministic PRNG so every run builds the same Vault. */
function rng(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
}

export function genVault(dir, projects = 20, repos = 12) {
  const r = rng(42);
  const pick = (a) => a[Math.floor(r() * a.length)];
  const para = (n = 3) => Array.from({ length: n }, () => {
    const w = Array.from({ length: 8 + Math.floor(r() * 10) }, () => pick(WORDS));
    w[0] = w[0][0].toUpperCase() + w[0].slice(1);
    if (r() < 0.25) w.push("#" + pick(TAGS));
    return w.join(" ") + ".";
  }).join(" ");
  const files = {};
  const put = (p, t) => (files[p] = t);
  const P = Array.from({ length: projects }, (_, i) => `project-${String(i + 1).padStart(2, "0")}`);
  const repoName = (p, j) => `${p.replace("project-", "svc")}-${WORDS[j % WORDS.length]}`;
  const eps = (k) => Array.from({ length: 6 }, (_, e) => `${["GET", "POST", "PUT", "DELETE"][e % 4]} /${WORDS[(k + e) % WORDS.length]}s${e % 2 ? "/{id}" : ""}`);
  const allRepos = P.flatMap((p, i) => Array.from({ length: repos }, (_, j) => ({ p, name: repoName(p, j), k: i * repos + j })));
  const today = new Date().toISOString().slice(0, 10);

  put("README.md", `---\ntype: note\n---\n# Scale vault\n\nGenerated. Projects: ${P.map((p) => `[[${p}/README]]`).join(", ")}.\n`);
  put("AGENTS.md", "# Agents\n\nRules for agents.\n");
  put("tags.md", TAGS.map((t) => `- #${t}: ${pick(WORDS)}`).join("\n") + "\n");
  put("repos.txt", allRepos.map((x) => x.name).join("\n") + "\n");
  for (let i = 0; i < 30; i++) put(`external/api-${i}.md`, `---\ntype: external-api\n---\n# External API ${i}\n\n## POST /v1/${WORDS[i % WORDS.length]}\n\n${para()}\n`);
  for (let i = 0; i < 30; i++) {
    const uses = Array.from({ length: 4 }, () => { const x = pick(allRepos); return `- [[${x.p}/${x.name}/endpoints#${pick(eps(x.k))}]]`; });
    put(`clients/client-${i}.md`, `---\ntype: client\n---\n# Client ${i}\n\nWho: ${para(1)}\n\nUses:\n${uses.join("\n")}\n`);
  }
  for (const p of P) {
    put(`${p}/README.md`, `---\ntype: project\n---\n# ${p}\n\n${para()}\n\nRepos: ${allRepos.filter((x) => x.p === p).map((x) => `[[${p}/${x.name}/README]]`).join(", ")}\n`);
    put(`${p}/overview.md`, `# Overview\n\n${para(5)}\n`);
    put(`${p}/archive/fixed-bugs.md`, `---\ntype: archive\n---\n# Fixed bugs\n\n### Old bug\n- closed: 2026-01-01\n${para()}\n`);
    put(`${p}/archive/done-todos.md`, `---\ntype: archive\n---\n# Done todos\n`);
  }
  for (const { p, name, k } of allRepos) {
    const base = `${p}/${name}`;
    const verified = new Date(Date.now() - Math.floor(r() * 90) * 864e5).toISOString().slice(0, 10);
    put(`${base}/README.md`, `---\ntype: repo\nrepo_url: https://example.invalid/${name}\nverified_commit: ${k.toString(16).padStart(7, "0")}\nverified_on: ${verified}\n---\n# ${name}\n\n${para()}\n\nSee [[${base}/endpoints]], [[${base}/architecture]] and [[${base}/bugs]].\n`);
    const ep = eps(k).map((e) => {
      const calls = Array.from({ length: 1 + Math.floor(r() * 2) }, () => { const x = pick(allRepos); return `- [[${x.p}/${x.name}/endpoints#${pick(eps(x.k))}]]`; });
      if (r() < 0.2) calls.push(`- [[external/api-${Math.floor(r() * 30)}#POST /v1/${WORDS[Math.floor(r() * 30) % WORDS.length]}]]`);
      return `## ${e}\n\nSummary: ${pick(VERBS)} a ${pick(WORDS)}. ${para(2)}\n\nCalls:\n${calls.join("\n")}\n`;
    });
    put(`${base}/endpoints.md`, `---\ntype: endpoint\n---\n# Endpoints\n\n${ep.join("\n")}`);
    put(`${base}/bugs.md`, `---\ntype: bugs\n---\n# Bugs\n\n${Array.from({ length: 4 }, () => `- [ ] ${para(1)} → [[${base}/endpoints#${pick(eps(k))}]]`).join("\n")}\n`);
    put(`${base}/todo.md`, `---\ntype: todo\n---\n# Todo\n\n${Array.from({ length: 5 }, () => `- [ ] ${para(1)}`).join("\n")}\n`);
    put(`${base}/architecture.md`, `---\ntype: architecture\n---\n# Architecture\n\n${para(6)}\n\n## Data flow\n\n${para(4)}\n\nDepends on [[${p}/${pick(allRepos.filter((x) => x.p === p)).name}/README]].\n`);
    put(`${base}/requirements.md`, `---\ntype: requirements\n---\n# Requirements\n\n${para(5)}\n`);
    put(`${base}/future.md`, `---\ntype: future\n---\n# Future\n\n${para(3)}\n`);
    for (let a = 1; a <= 5; a++) put(`${base}/adr/000${a}-${pick(WORDS)}.md`, `---\ntype: adr\n---\n# ADR ${a}\n\nDate: ${today}\n\n${para(4)}\n`);
    for (let n = 1; n <= 9; n++) put(`${base}/notes/note-${n}.md`, `# Note ${n}\n\n${para(4)}\n\nRelated: [[${base}/notes/note-${(n % 9) + 1}]] [[${base}/README]]\n`);
  }
  for (const [p, t] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
    fs.writeFileSync(path.join(dir, p), t);
  }
  return Object.keys(files).length;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = process.argv[2] || fs.mkdtempSync(path.join(os.tmpdir(), "constellation-scale-"));
  const n = genVault(dir, Number(process.argv[3] || 20), Number(process.argv[4] || 12));
  console.log(dir, n, "files");
}
