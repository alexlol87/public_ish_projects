import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { starterFiles, planScaffold, withExcluded, withColorGroups, colorGroupsLeftAlone, chooseTemplatesFolder, AGENTS_MD, TEMPLATES } from "./scaffold.ts";

test("starter set matches the standalone app's (minus its own .constellation folder)", () => {
  const paths = starterFiles().map((f) => f.path).sort();
  const templates = ["adr", "architecture", "archive", "bugs", "client", "endpoints", "external-api", "future", "project", "repo", "requirements", "todo"];
  assert.deepEqual(paths, ["AGENTS.md", "README.md", "repos.txt", "tags.md", ...templates.map((t) => `templates/${t}.md`)].sort());
});

const text = (path: string) => starterFiles().find((f) => f.path === path)!.text;

test("AGENTS.md covers the workflows and hard rules", () => {
  const a = text("AGENTS.md");
  for (const s of ["## Ingest", "## Refresh", "## Answer", "repos.txt", "Archive", "Client", "unknown", "tags.md", "sibling"]) assert.ok(a.includes(s), s);
  assert.ok(a.startsWith("# Agent rules\n"));
  assert.ok(a.endsWith("`[[<project>/<repo>/README]]`."));
  assert.ok(a.includes("```markdown\n### Total ignores discounts\n- closed: YYYY-MM-DD\n- source: [[shop/orders/endpoints#POST /orders]]\n"));
});

test("templates give the right Note types and Repo keys", () => {
  const types: Record<string, string> = { project: "project", repo: "repo", endpoints: "endpoint", architecture: "architecture", adr: "adr", requirements: "requirements", future: "future", bugs: "bugs", todo: "todo", "external-api": "external-api", client: "client", archive: "archive" };
  for (const [name, type] of Object.entries(types)) assert.ok(text(`templates/${name}.md`).startsWith(`---\ntype: ${type}\n`), name);
  const repo = text("templates/repo.md");
  for (const k of ["repo_url", "verified_commit", "verified_on"]) assert.ok(repo.includes(`\n${k}: unknown\n`), k);
  assert.ok(text("templates/endpoints.md").includes("\nCalls:\n- [[other-repo/endpoints#GET /path]]\n"));
  assert.ok(text("templates/client.md").endsWith("\nUses:\n- [[project/repo/endpoints#GET /path]]\n"));
});

test("root starter files have the standalone app's text", () => {
  assert.equal(text("README.md"), "# Vault\n\nWhat this vault covers.\n");
  assert.equal(text("repos.txt"), "# One repository name per line.\n");
  assert.equal(text("tags.md"), "# Tags\n\n- #example: what this tag means\n");
});

test("an empty vault gets every starter folder and file", () => {
  const plan = planScaffold(() => false);
  assert.deepEqual(plan.folders, ["templates", "external", "clients"]);
  assert.equal(plan.files.length, 16);
  assert.deepEqual(plan.skipped, []);
});

test("existing files and folders are skipped, never planned for writing", () => {
  const have = new Set(["README.md", "external", "templates", "templates/repo.md"]);
  const plan = planScaffold((p) => have.has(p));
  assert.deepEqual(plan.folders, ["clients"]);
  assert.deepEqual(plan.skipped, ["README.md", "templates/repo.md"]);
  assert.ok(!plan.files.some((f) => have.has(f.path)));
  assert.equal(plan.files.length, 14);
});

test("Excluded files gain the app-only files once, keeping the user's own", () => {
  const want = ["AGENTS.md", "repos.txt", "tags.md", "templates/"];
  assert.deepEqual(withExcluded(null), want);
  assert.deepEqual(withExcluded(["private/", "tags.md"]), ["private/", "tags.md", "AGENTS.md", "repos.txt", "templates/"]);
  assert.deepEqual(withExcluded(withExcluded([])), want);
});

test("graph colour groups: one per Note type, replacing ours, keeping the user's", () => {
  const ours = withColorGroups(undefined);
  assert.deepEqual(ours.map((g) => g.query), ["[type:project]", "[type:repo]", "[type:endpoint]", '[type:"external-api"]', "[type:client]"]);
  assert.deepEqual(ours[0].color, { a: 1, rgb: 0xd4a72c });
  const mine = { query: "tag:#urgent", color: { a: 1, rgb: 0xff0000 } };
  const picked = { query: "[type:repo]", color: { a: 1, rgb: 1 } };
  const merged = withColorGroups([mine, picked]);
  assert.deepEqual(merged, [mine, picked, ...ours.filter((g) => g.query !== picked.query)]);
  assert.deepEqual(withColorGroups(ours), ours);
  assert.deepEqual(colorGroupsLeftAlone([mine, picked]), ["[type:repo]"]);
  assert.deepEqual(colorGroupsLeftAlone(undefined), []);
});

test("templates folder: an existing choice is kept, only an unset one is filled in", () => {
  assert.deepEqual(chooseTemplatesFolder(undefined), { folder: "templates", keptFrom: null });
  assert.deepEqual(chooseTemplatesFolder("  "), { folder: "templates", keptFrom: null });
  assert.deepEqual(chooseTemplatesFolder("My templates"), { folder: "My templates", keptFrom: "My templates" });
});

// Drift check against the standalone app's agent_files.rs (same repo, sibling folder).
const RUST = fileURLToPath(new URL("../../constellation/core/src/agent_files.rs", import.meta.url));
test("AGENTS.md and templates equal the standalone app's text", { skip: !existsSync(RUST) && `${RUST} not found` }, () => {
  const rs = readFileSync(RUST, "utf8");
  const raws = [...rs.matchAll(/r####"([\s\S]*?)"####/g)].map((m) => m[1]);
  const names = [...rs.matchAll(/\(\s*"([^"]+)",\s*r####"/g)].map((m) => m[1]);
  const agents = /AGENTS_MD: &str = r####"([\s\S]*?)"####/.exec(rs)![1];
  assert.equal(AGENTS_MD, agents);
  assert.equal(names.length, 12);
  assert.deepEqual(Object.keys(TEMPLATES).sort(), [...names].sort());
  for (const [i, name] of names.entries()) assert.equal(TEMPLATES[name], raws[raws.length - names.length + i], name);
});
