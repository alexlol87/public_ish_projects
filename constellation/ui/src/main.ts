import { createEditor } from "./editor/editor";
import { applyTheme } from "./lib/themes";

const sample = `# Constellation

Some **bold**, *italic*, ~~struck~~ and <u>underlined</u> text with \`code\`.
Link to [[shop/orders-service/README|orders]] and a [[missing-note]], tagged #payments.

> A quote

- [ ] open task
- [x] done task

| Endpoint | Status |
|---|---|
| POST /orders | implemented |

\`\`\`
fenced code
\`\`\`
`;

applyTheme("System");
createEditor(document.getElementById("app")!, {
  doc: sample,
  isBrokenLink: (t) => t === "missing-note",
  linkCompletions: async (typed) => ["shop/orders-service/README", "missing-note"].filter((s) => s.includes(typed)),
  tagCompletions: async (p) => ["payments", "pci"].filter((s) => s.startsWith(p)),
  onOpenLink: (t, newTab) => console.log("open", t, newTab),
  onTagClick: (t) => console.log("tag", t),
  onTickTask: (o) => console.log("tick", o),
});
