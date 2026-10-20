// Archive ticked items (ADR 0002): ticked Bugs / Todos of a Repo's bugs.md / todo.md move to the Project's archive Note.
// Port of constellation/core/src/archiver.rs, but for every ticked item of the Note at once.
import { linksIn } from "./relations.ts";

export interface Archived {
  text: string; // the Note without its ticked items
  count: number;
  archivePath: string;
  entries: string; // the archive entries, each ending in "\n"
  heading: string; // archive Note title, used when it must be created
}

// groups: 1 indent, 2 box char, 3 rest of the line
const TASK = /^([ \t]*)[-*+] \[([ xX])\] ?(.*?)\r?\n?$/;
const indent = (s: string) => s.length - s.trimStart().length;

/** A Repo's bugs.md or todo.md, by file name. */
export const isTaskNote = (name: string) => name === "bugs.md" || name === "todo.md";

/** `resolve` maps a Link target to the vault path of its Note, without `.md`. Null: not a Repo's bugs.md / todo.md, or nothing ticked. */
export function archiveTicked(path: string, text: string, on: Date, resolve: (target: string) => string = (t) => t): Archived | null {
  const parts = path.split("/");
  const file = parts[parts.length - 1];
  if (parts.length < 3 || !isTaskNote(file)) return null;
  const repo = parts.slice(0, -1).join("/");
  const closed = on.toISOString().slice(0, 10); // UTC, like staleness and the standalone app

  const lines = text.split(/(?<=\n)/);
  let kept = "";
  const entries: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const m = TASK.exec(lines[i]);
    if (!m || m[2] === " ") {
      kept += lines[i];
      continue;
    }
    // The item: its line plus the more-indented lines after it.
    let end = i + 1;
    while (end < lines.length && lines[end].trim() !== "" && indent(lines[end]) > m[1].length) end++;
    const body = m[3].trim();
    const title = body.split(" → ")[0].trim();
    const rest = lines.slice(i + 1, end).map((l) => l.trim()).filter(Boolean).join(" ");
    const link = linksIn(lines.slice(i, end).join(""))[0];
    const source = link ? `[[${resolve(link.target)}${link.heading ? `#${link.heading}` : ""}]]` : `[[${repo}/README]]`;
    entries.push(`### ${title}\n- closed: ${closed}\n- source: ${source}\n- what: ${rest || title}\n- fix: unknown\n`);
    i = end - 1;
  }
  if (!entries.length) return null;
  const bug = file === "bugs.md";
  return {
    text: kept,
    count: entries.length,
    archivePath: `${parts[0]}/archive/${bug ? "fixed-bugs.md" : "done-todos.md"}`,
    entries: entries.join("\n"),
    heading: bug ? "Fixed bugs" : "Done todos",
  };
}

/** The archive Note's new text. `old` null: the Note doesn't exist yet and is created with `type: archive`. */
export function appendToArchive(old: string | null, a: Archived): string {
  if (old === null) return `---\ntype: archive\n---\n# ${a.heading}\n\n${a.entries}`;
  return old + (old === "" ? "" : old.endsWith("\n") ? "\n" : "\n\n") + a.entries;
}
