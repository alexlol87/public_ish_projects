/** Role -> colour (hex `#RRGGBB`). */
export interface Palette {
  isDark: boolean;
  background: string; text: string; accent: string; heading: string; link: string;
  code: string; tag: string; folderNode: string; noteNode: string; stale: string;
}

export const THEME_CHOICES = ["Light", "Dark", "Dracula", "One Dark", "System"] as const;
export type ThemeChoice = (typeof THEME_CHOICES)[number];

const palettes: Record<Exclude<ThemeChoice, "System">, Palette> = {
  Light: { isDark: false, background: "#FFFFFF", text: "#24292F", accent: "#0969DA", heading: "#8250DF", link: "#0969DA",
    code: "#CF222E", tag: "#1A7F37", folderNode: "#BF8700", noteNode: "#0969DA", stale: "#D1242F" },
  Dark: { isDark: true, background: "#1E1E1E", text: "#D4D4D4", accent: "#4DA3FF", heading: "#C586C0", link: "#4DA3FF",
    code: "#CE9178", tag: "#4EC9B0", folderNode: "#E5A50A", noteNode: "#4DA3FF", stale: "#F85149" },
  Dracula: { isDark: true, background: "#282A36", text: "#F8F8F2", accent: "#BD93F9", heading: "#FF79C6", link: "#8BE9FD",
    code: "#F1FA8C", tag: "#50FA7B", folderNode: "#FFB86C", noteNode: "#BD93F9", stale: "#FF5555" },
  "One Dark": { isDark: true, background: "#282C34", text: "#ABB2BF", accent: "#61AFEF", heading: "#E06C75", link: "#61AFEF",
    code: "#98C379", tag: "#56B6C2", folderNode: "#D19A66", noteNode: "#61AFEF", stale: "#BE5046" },
};

const systemQuery = () => globalThis.matchMedia?.("(prefers-color-scheme: dark)");

/** `systemIsDark` only matters for "System". */
export function palette(choice: ThemeChoice, systemIsDark = !!systemQuery()?.matches): Palette {
  return palettes[choice === "System" ? (systemIsDark ? "Dark" : "Light") : choice];
}

/** Sets `--background`, `--text`, ... (kebab-case palette keys) and `color-scheme` on `el`. */
export function applyTheme(choice: ThemeChoice, el: HTMLElement = document.documentElement, systemIsDark?: boolean) {
  const { isDark, ...colors } = palette(choice, systemIsDark);
  for (const [k, v] of Object.entries(colors)) el.style.setProperty("--" + k.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase()), v);
  el.style.setProperty("color-scheme", isDark ? "dark" : "light");
}

/** Calls `onChange` when the OS switches between light and dark (re-run `applyTheme` for "System"). Returns an unsubscribe. */
export function watchSystemTheme(onChange: (isDark: boolean) => void): () => void {
  const q = systemQuery();
  if (!q) return () => {};
  const f = (e: MediaQueryListEvent) => onChange(e.matches);
  q.addEventListener("change", f);
  return () => q.removeEventListener("change", f);
}
