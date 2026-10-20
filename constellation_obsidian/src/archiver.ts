// Archive ticked items (ADR 0002): ticked Bugs / Todos of a Repo's bugs.md / todo.md move to the Project's archive Note.
// Port of constellation/core/src/archiver.rs, but for every ticked item of the Note at once.
import { linksIn } from "./relations.ts";
import { repoOf } from "./repo.ts";

export interface Archived {
  text: string; // the Note without its ticked items
  keep: number[]; // the indices of the lines of the Note that remain, ascending
  count: number;
  archivePath: string;
  entries: string; // the archive entries, each ending in "\n"
  heading: string; // archive Note title, used when it must be created
}

// groups: 1 indent, 2 box char, 3 rest of the line
const TASK = /^([ \t]*)(?:[-*+]|\d+[.)]) \[([ xX])\] ?(.*?)\r?\n?$/;
const indent = (s: string) => s.length - s.trimStart().length;

/** A Repo's bugs.md or todo.md, by file name. */
export const isTaskNote = (name: string) => name === "bugs.md" || name === "todo.md";

/** `resolve` maps a Link target to the vault path of its Note, without `.md`. Null: not a Repo's bugs.md / todo.md, or nothing ticked. */
export function archiveTicked(path: string, text: string, on: Date, resolve: (target: string) => string = (t) => t): Archived | null {
  const file = path.split("/").pop()!;
  const repo = repoOf(path);
  if (!repo || !isTaskNote(file)) return null;
  const closed = on.toISOString().slice(0, 10); // UTC, like staleness and the standalone app

  const lines = text.split(/(?<=\n)/);
  const keep: number[] = [];
  let fence = false;
  const entries: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*(```|~~~)/.test(lines[i])) fence = !fence;
    const m = fence ? null : TASK.exec(lines[i]);
    if (!m || m[2] === " ") {
      keep.push(i);
      continue;
    }
    // The item: its line plus the more-indented lines after it. An unticked child task and its own detail lines stay in the Note.
    let end = i + 1;
    while (end < lines.length && lines[end].trim() !== "" && indent(lines[end]) > m[1].length) end++;
    const own: string[] = [];
    for (let j = i + 1; j < end; j++) {
      const c = TASK.exec(lines[j]);
      if (c?.[2] !== " ") {
        own.push(lines[j]);
        continue;
      }
      keep.push(j);
      while (j + 1 < end && indent(lines[j + 1]) > c[1].length) keep.push(++j);
    }
    const title = m[3].split(" → ")[0].trim() || "(no text)";
    const rest = own.map((l) => l.trim()).filter(Boolean).join(" ");
    const link = linksIn([lines[i], ...own].join(""))[0];
    const source = link ? `[[${resolve(link.target)}${link.heading ? `#${link.heading}` : ""}]]` : `[[${repo.folder}/README]]`;
    entries.push(`### ${title}\n- closed: ${closed}\n- source: ${source}\n- what: ${rest || title}\n- fix: unknown\n`);
    i = end - 1;
  }
  if (!entries.length) return null;
  const bug = file === "bugs.md";
  return {
    text: keep.map((i) => lines[i]).join(""),
    keep,
    count: entries.length,
    archivePath: `${repo.project}/archive/${bug ? "fixed-bugs.md" : "done-todos.md"}`,
    entries: entries.join("\n"),
    heading: bug ? "Fixed bugs" : "Done todos",
  };
}

/** The archive Note's new text. `old` null: the Note doesn't exist yet and is created with `type: archive`. */
export function appendToArchive(old: string | null, a: Archived): string {
  if (old === null) return `---\ntype: archive\n---\n# ${a.heading}\n\n${a.entries}`;
  const text = old + (old === "" ? "" : old.endsWith("\n") ? "\n" : "\n\n") + a.entries;
  return old.includes("\r\n") ? old + text.slice(old.length).replace(/\n/g, "\r\n") : text;
}

/** Move a cursor position inside `text` (it may point past the end after the text got shorter). */
export function clampPos(text: string, pos: { line: number; ch: number }) {
  const lines = text.split("\n");
  const line = Math.min(pos.line, lines.length - 1);
  return { line, ch: Math.min(pos.ch, lines[line].length) };
}

/** Where a cursor goes when only the lines not in `keep` were removed: it stays on its text, or, if its line went, moves to where that line was. */
export function mapCursor(keep: number[], pos: { line: number; ch: number }) {
  const at = keep.indexOf(pos.line);
  return at >= 0 ? { line: at, ch: pos.ch } : { line: keep.filter((i) => i < pos.line).length, ch: 0 };
}
