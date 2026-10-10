'use strict';
// Which colors the open windows use. Every VS Code window runs its own extension host process, so each window
// records { id, pid, color } in one small JSON file; an entry whose process is gone belongs to a closed window and
// is ignored. Nothing polls: the file is only read and written when a window opens, closes or changes color.

const fs = require('fs');
const path = require('path');
const { pickColor } = require('./colors');

function isAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

function read(file) {
  try {
    const entries = JSON.parse(fs.readFileSync(file, 'utf8'));
    return Array.isArray(entries) ? entries.filter((e) => e && typeof e.id === 'string') : [];
  } catch {
    return [];
  }
}

function write(file, entries) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(entries));
  fs.renameSync(tmp, file);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Runs `fn` while holding a lock directory next to `file`, so windows opening together don't pick the same color. */
async function withLock(file, fn) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const lock = `${file}.lock`;
  let held = false;
  for (let attempt = 0; attempt < 150 && !held; attempt++) {
    try {
      fs.mkdirSync(lock);
      held = true;
    } catch (err) {
      if (err.code !== 'EEXIST') throw err;
      try {
        // A window that crashed while holding the lock leaves it behind.
        if (Date.now() - fs.statSync(lock).mtimeMs > 2000) fs.rmdirSync(lock);
      } catch {}
      await sleep(20);
    }
  }
  try {
    return fn();
  } finally {
    if (held) fs.rmSync(lock, { recursive: true, force: true });
  }
}

/** Entries of other windows that are still open. */
function others(entries, id, alive = isAlive) {
  return entries.filter((e) => e.id !== id && alive(e.pid));
}

/**
 * Records a color for window `id` and returns it. With `force` the color is `preferred` even if another window has
 * it (the user chose it); otherwise `preferred` is used only when free.
 */
async function claim(file, { id, pid = process.pid, preferred, palette, force = false, alive = isAlive }) {
  return withLock(file, () => {
    const rest = others(read(file), id, alive);
    const color = force && preferred ? preferred : pickColor(rest.map((e) => e.color), preferred, palette);
    write(file, [...rest, { id, pid, color }]);
    return color;
  });
}

/** Drops window `id` (and closed windows) from the file. Synchronous so it can run while the window closes. */
function release(file, id, alive = isAlive) {
  try {
    write(file, others(read(file), id, alive));
  } catch {}
}

module.exports = { isAlive, read, claim, release, others };
