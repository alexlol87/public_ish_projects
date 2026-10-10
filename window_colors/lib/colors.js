'use strict';
// Pure color helpers: no vscode import, so `node --test` covers them without an editor.

// Ten colors that stay easy to tell apart next to each other, on light and dark themes.
const PALETTE = [
  '#d32f2f', // red
  '#1976d2', // blue
  '#388e3c', // green
  '#f57c00', // orange
  '#7b1fa2', // purple
  '#00838f', // teal
  '#c2185b', // pink
  '#fbc02d', // yellow
  '#5d4037', // brown
  '#455a64', // slate
];

// Keys this extension writes into workbench.colorCustomizations (when tintFolderWindows or tintEmptyWindows is on).
// They include every key Peacock writes by default, so colors a folder still has from Peacock are replaced.
const CHROME_KEYS = [
  'window.activeBorder',
  'window.inactiveBorder',
  'titleBar.activeBackground',
  'titleBar.activeForeground',
  'titleBar.inactiveBackground',
  'titleBar.inactiveForeground',
  'commandCenter.border',
  'activityBar.background',
  'activityBar.activeBackground',
  'activityBar.foreground',
  'activityBar.inactiveForeground',
  'activityBarBadge.background',
  'activityBarBadge.foreground',
  'statusBar.background',
  'statusBar.foreground',
  'statusBarItem.hoverBackground',
  'statusBarItem.remoteBackground',
  'statusBarItem.remoteForeground',
  'sash.hoverBorder',
];

function isHexColor(value) {
  return typeof value === 'string' && /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(value.trim());
}

/** '#ABC' or ' #aabbcc ' -> '#aabbcc'; anything else -> null. */
function normalizeHex(value) {
  if (!isHexColor(value)) return null;
  let hex = value.trim().slice(1).toLowerCase();
  if (hex.length === 3) hex = hex.split('').map((c) => c + c).join('');
  return '#' + hex;
}

/** The user's palette setting if it has at least one valid color, else the built-in one. */
function resolvePalette(custom) {
  const valid = Array.isArray(custom) ? [...new Set(custom.map(normalizeHex).filter(Boolean))] : [];
  return valid.length ? valid : PALETTE;
}

/** FNV-1a, so the same folder always prefers the same color. */
function hashString(text) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

function preferredFor(key, palette = PALETTE) {
  return key ? palette[hashString(key) % palette.length] : null;
}

/**
 * The color for a new window: `preferred` when no other open window has it, otherwise the first palette color
 * nobody uses (searching from the preferred one), otherwise the least used one.
 */
function pickColor(taken, preferred, palette = PALETTE) {
  const used = new Map();
  for (const color of taken.map(normalizeHex).filter(Boolean)) used.set(color, (used.get(color) || 0) + 1);
  const want = normalizeHex(preferred);
  if (want && !used.has(want)) return want;
  const start = Math.max(0, palette.indexOf(want));
  for (let i = 0; i < palette.length; i++) {
    const color = palette[(start + i) % palette.length];
    if (!used.has(color)) return color;
  }
  return palette.reduce((best, color) => (used.get(color) < used.get(best) ? color : best), palette[0]);
}

/** Black or white, whichever reads better on `hex` (WCAG relative luminance). */
function foregroundFor(hex) {
  const value = normalizeHex(hex) || '#000000';
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(value.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return luminance > 0.179 ? '#000000' : '#ffffff';
}

/** The workbench.colorCustomizations entries for the window border, title bar, activity bar and status bar. */
function chromeColors(hex) {
  const bg = normalizeHex(hex);
  const fg = foregroundFor(bg);
  return {
    'window.activeBorder': bg,
    'window.inactiveBorder': bg + 'cc',
    'titleBar.activeBackground': bg,
    'titleBar.activeForeground': fg,
    'titleBar.inactiveBackground': bg + 'cc',
    'titleBar.inactiveForeground': fg + '99',
    'commandCenter.border': fg + '99',
    'activityBar.background': bg,
    'activityBar.activeBackground': bg,
    'activityBar.foreground': fg,
    'activityBar.inactiveForeground': fg + '99',
    'activityBarBadge.background': fg,
    'activityBarBadge.foreground': bg,
    'statusBar.background': bg,
    'statusBar.foreground': fg,
    'statusBarItem.hoverBackground': fg + '22',
    'statusBarItem.remoteBackground': bg,
    'statusBarItem.remoteForeground': fg,
    'sash.hoverBorder': bg,
  };
}

/** `customizations` with this extension's keys set to `hex`, or removed when `hex` is null. Others are kept. */
function mergeChrome(customizations, hex) {
  const next = { ...(customizations || {}) };
  for (const key of CHROME_KEYS) delete next[key];
  return hex ? { ...next, ...chromeColors(hex) } : next;
}

module.exports = {
  PALETTE,
  CHROME_KEYS,
  isHexColor,
  normalizeHex,
  resolvePalette,
  hashString,
  preferredFor,
  pickColor,
  foregroundFor,
  chromeColors,
  mergeChrome,
};
