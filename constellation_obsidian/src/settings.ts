// Plugin settings, pure (no obsidian import).
export interface Settings {
  stalenessDays: number;
}

export function withDefaults(saved: Partial<Settings> | null): Settings {
  return { stalenessDays: 30, ...saved };
}

/** The settings field's text as whole days, or null if it isn't a whole number >= 0. */
export function parseDays(text: string): number | null {
  const t = text.trim();
  return /^\d+$/.test(t) ? Number(t) : null;
}
