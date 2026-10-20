// Repo detection, staleness and copy prompts, pure (no obsidian import). Ported from the standalone app's core.
export interface Repo {
  folder: string;
  project: string;
  name: string;
}

const APP_ONLY_TOP = ["agents.md", "repos.txt", "tags.md", "templates", ".constellation"];

/** The Repo a vault-relative Note path is in: `project/repo/...`, outside external/, clients/, archive/ and app-only files. */
export function repoOf(path: string): Repo | null {
  const c = path.split("/").filter((s) => s);
  if (c.length < 3) return null;
  const [project, name] = c;
  if (APP_ONLY_TOP.includes(project.toLowerCase()) || ["external", "clients", "archive"].includes(project) || name === "archive") return null;
  return { folder: `${project}/${name}`, project, name };
}

export type Staleness = { kind: "verified"; days: number } | { kind: "never" } | { kind: "malformed" };

/** Parse a strict `YYYY-MM-DD` to UTC days since the epoch; the round trip rejects loose forms like `2026-6-5`. */
function utcDays(s: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const t = Date.parse(s + "T00:00:00Z");
  return Number.isNaN(t) || new Date(t).toISOString().slice(0, 10) !== s ? null : t / 86_400_000;
}

/** `verifiedOn` is the README's `verified_on`; `today` is today's UTC date as `YYYY-MM-DD`. */
export function staleness(verifiedOn: string | undefined, today: string): Staleness {
  const s = (verifiedOn ?? "").trim().replace(/^["']+|["']+$/g, "");
  if (!s) return { kind: "never" };
  const d = utcDays(s);
  const now = utcDays(today);
  return d === null || now === null ? { kind: "malformed" } : { kind: "verified", days: now - d };
}
/** Past the threshold, in the future, never verified, or unreadable. */
export function isStale(s: Staleness, threshold: number): boolean {
  return !(s.kind === "verified" && s.days >= 0 && s.days <= threshold);
}

export function label(s: Staleness): string {
  if (s.kind === "never") return "never verified";
  if (s.kind === "malformed") return "verified date unreadable";
  if (s.days < 0) return "date is in the future";
  if (s.days === 0) return "verified today";
  return `verified ${s.days} day${s.days === 1 ? "" : "s"} ago`;
}
export function ingestPrompt(repo: string): string {
  return `Follow AGENTS.md in this Vault and run the Ingest workflow for the repository "${repo}".`;
}

export function refreshPrompt(repo: string): string {
  return `Follow AGENTS.md in this Vault and run the Refresh workflow for the repository "${repo}".`;
}
