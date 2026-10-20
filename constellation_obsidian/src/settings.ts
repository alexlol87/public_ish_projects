// Plugin settings, pure (no obsidian import).
export interface Settings {
  stalenessDays: number;
}

export function withDefaults(saved: Partial<Settings> | null): Settings {
  return { stalenessDays: 30, ...saved };
}

export const MAX_DAYS = 36500;

/** The settings field's text as whole days, or null if it isn't a whole number from 1 to MAX_DAYS (leading zeros are fine). */
export function parseDays(text: string): number | null {
  const t = text.trim();
  const n = /^\d+$/.test(t) ? Number(t) : 0;
  return n >= 1 && n <= MAX_DAYS ? n : null;
}
