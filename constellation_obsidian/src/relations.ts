/** Calls/Uses parsing and Endpoint relations (pure; ported from constellation/core parser.rs and graph.rs). */

export type Link = { target: string; heading: string | null };
export type Section = { heading: string; links: Link[] };
type Heading = { level: number; title: string; line: number };
/** `uses` is filled only in Client Notes (frontmatter `type: client`). */
export type ParsedNote = { headings: Heading[]; calls: Section[]; uses: Link[] };

const HEADING = /^(#{1,6}) +(\S.*?) *$/;
const CODE = /`[^`]+`/g;
const LINK = /\[\[([^\[\]|#]+)(?:#([^\[\]|]*))?(?:\|([^\[\]]*))?\]\]/g;
const ENDPOINT = /^`?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \//;

/** A heading title as Links name it: backticks dropped (`` `GET /a` `` -> `GET /a`). */
const plain = (title: string) => title.replaceAll("`", "");

/** Links in `text`, outside inline code (code spans don't cross lines). */
export const linksIn = (text: string): Link[] => text.split(/\r?\n/).flatMap(lineLinks);

/** Links on one line, outside inline code. */
function lineLinks(s: string): Link[] {
  const code = [...s.matchAll(CODE)].map((m) => [m.index, m.index + m[0].length]);
  return [...s.matchAll(LINK)]
    .filter((m) => !code.some(([a, b]) => m.index < b && a < m.index + m[0].length))
    .map((m) => ({ target: m[1].trim(), heading: m[2] || null }));
}

/** The Endpoint heading a line sits in: the nearest one above, unless a sibling or parent heading comes in between. */
function endpointHeading(headings: Heading[], line: number): Heading | null {
  let shallowest = Infinity;
  for (const h of [...headings].reverse().filter((h) => h.line <= line)) {
    if (ENDPOINT.test(h.title)) return shallowest > h.level ? h : null;
    shallowest = Math.min(shallowest, h.level);
  }
  return null;
}

export function parseNote(text: string): ParsedNote {
  const all = text.split(/\r?\n/);
  let start = 0;
  let client = false;
  if (all[0]?.trimEnd() === "---") {
    const close = all.findIndex((l, i) => i > 0 && l.trimEnd() === "---");
    if (close > 0) {
      start = close + 1;
      client = all.slice(1, close).some((l) => /^type:\s*client\s*$/.test(l));
    }
  }
  // Body lines outside fenced code, with their line numbers.
  const body: { text: string; line: number }[] = [];
  let fence = false;
  for (let i = start; i < all.length; i++) {
    if (all[i].startsWith("```")) fence = !fence;
    else if (!fence) body.push({ text: all[i], line: i });
  }
  const headings: Heading[] = [];
  for (const l of body) {
    const m = HEADING.exec(l.text);
    if (m) headings.push({ level: m[1].length, title: m[2], line: l.line });
  }
  const calls: Section[] = [];
  const uses: Link[] = [];
  for (let i = 0; i < body.length; i++) {
    const label = body[i].text.trim();
    if (label !== "Calls:" && label !== "Uses:") continue;
    const at = body[i].line;
    const links: Link[] = [];
    while (i + 1 < body.length && /^[-*] /.test(body[i + 1].text.trim())) links.push(...lineLinks(body[++i].text));
    if (label === "Uses:") {
      if (client) uses.push(...links);
      continue;
    }
    const h = endpointHeading(headings, at);
    if (h) calls.push({ heading: plain(h.title), links });
  }
  return { headings, calls, uses };
}

/** The Endpoint (plain title) the 0-based `line` sits in, else null. */
export function endpointAt(note: ParsedNote, line: number): string | null {
  const h = endpointHeading(note.headings, line);
  return h && plain(h.title);
}

/** Note path a Link target resolves to from Note `from`, or null when missing. */
export type Resolve = (target: string, from: string) => string | null;
/** A Link out of a Note; broken when its Note is missing or has no such heading. */
export type Target = Link & { path: string | null; broken: boolean };
/** A Note (and the Endpoint in it, for a Call) that points at an Endpoint. */
export type Ref = { path: string; heading: string | null };

const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

/** Resolves `links` written in Note `from`, marking broken ones. */
export function resolveLinks(notes: Map<string, ParsedNote>, resolve: Resolve, from: string, links: Link[]): Target[] {
  return links.map((l) => {
    const path = resolve(l.target, from);
    const note = path === null ? undefined : notes.get(path);
    const headingOk = l.heading === null || !!note?.headings.some((h) => same(plain(h.title), plain(l.heading!)));
    return { ...l, path, broken: path === null || !headingOk };
  });
}

/** Relations of Endpoint `heading` in Note `path`: what it Calls, what Calls it, which Clients use it. */
export function endpointRelations(notes: Map<string, ParsedNote>, resolve: Resolve, path: string, heading: string) {
  const hits = (from: string) => (l: Link) => resolve(l.target, from) === path && l.heading !== null && same(plain(l.heading), heading);
  const calls: Target[] = [];
  const calledBy: Ref[] = [];
  const usedBy: Ref[] = [];
  for (const [p, note] of notes) {
    for (const s of note.calls) {
      if (p === path && same(s.heading, heading)) calls.push(...resolveLinks(notes, resolve, p, s.links));
      if (s.links.some(hits(p))) calledBy.push({ path: p, heading: s.heading });
    }
    if (note.uses.some(hits(p))) usedBy.push({ path: p, heading: null });
  }
  return { calls, calledBy, usedBy };
}
