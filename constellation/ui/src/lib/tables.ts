/** If a table starts on `lines[i]` (header row + delimiter row), returns its line count and column-aligned text. */
export function table(lines: string[], i: number): { count: number; rendered: string } | null {
  const cells = (l: string): string[] | null => {
    const t = l.trim();
    if (!t.startsWith("|")) return null;
    const parts = t.split("|").map((s) => s.trim());
    parts.shift();
    if (t.endsWith("|")) parts.pop();
    return parts;
  };
  const head = cells(lines[i] ?? ""), delim = cells(lines[i + 1] ?? "");
  if (!head || !delim || delim.length !== head.length || !delim.every((d) => /^:?-+:?$/.test(d))) return null;
  const rows = [head];
  let n = 2;
  for (let c; i + n < lines.length && (c = cells(lines[i + n])); n++) rows.push(c);
  const cols = head.length;
  // ponytail: widths by UTF-16 length, not display width; upgrade for CJK/emoji cells.
  const widths = Array.from({ length: cols }, (_, c) => Math.max(1, ...rows.map((r) => (r[c] ?? "").length)));
  const line = (r: string[]) => "| " + widths.map((w, c) => (r[c] ?? "").padEnd(w)).join(" | ") + " |";
  const dash = widths.map((w) => "-".repeat(w));
  return { count: n, rendered: [line(head), line(dash), ...rows.slice(1).map(line)].join("\n") };
}
