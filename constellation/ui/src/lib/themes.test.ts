import { expect, test } from "vitest";
import { applyTheme, palette, THEME_CHOICES } from "./themes";

test("choices and palettes", () => {
  expect([...THEME_CHOICES]).toEqual(["Light", "Dark", "Dracula", "One Dark", "System"]);
  expect(palette("Dracula", false).background).toBe("#282A36");
  expect(palette("One Dark", false).background).toBe("#282C34");
  expect(palette("Dracula", false).isDark).toBe(true);
  expect(palette("Light", true).isDark).toBe(false);
  expect(palette("System", true)).toEqual(palette("Dark", false));
  expect(palette("System", false)).toEqual(palette("Light", true));
  for (const t of THEME_CHOICES) {
    const { isDark: _, ...colors } = palette(t, false);
    for (const h of Object.values(colors)) expect(h).toMatch(/^#[0-9A-F]{6}$/);
  }
});

test("applyTheme sets CSS custom properties", () => {
  const props: Record<string, string> = {};
  const el = { style: { setProperty: (k: string, v: string) => (props[k] = v) } } as unknown as HTMLElement;
  applyTheme("System", el, true);
  expect(props["--background"]).toBe("#1E1E1E");
  expect(props["--folder-node"]).toBe("#E5A50A");
  expect(props["color-scheme"]).toBe("dark");
  applyTheme("Light", el);
  expect(props["--background"]).toBe("#FFFFFF");
  expect(props["color-scheme"]).toBe("light");
});
