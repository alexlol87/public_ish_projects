export const AUTOSAVE_DELAY_MS = 1000;

/**
 * Open Notes (tabs), their text and unsaved edits. Pure state, no IO: the app reads and writes files
 * (through the backend), owns the timer, and tells us the results.
 */
export class NoteTabs {
  paths: string[] = [];
  active: string | null = null;
  private texts = new Map<string, string>();
  private lastEdit = new Map<string, number>(); // present = unsaved
  private onDisk = new Map<string, string>(); // last text read or written; tells our own save echoes from outside edits
  private conflicts = new Map<string, string>(); // disk text waiting for the "Reload from disk / Keep mine" choice
  private revisions = new Map<string, number>();

  text(path: string) { return this.texts.get(path); }
  /** Disk text of a Note with unsaved edits that also changed on disk (show the banner), else undefined. */
  conflict(path: string) { return this.conflicts.get(path); }
  /** Bumps each time the text is replaced from disk; the app uses it to reset the editor's document. */
  revision(path: string) { return this.revisions.get(path) ?? 0; }
  get hasConflicts() { return this.conflicts.size > 0; }
  get hasPendingEdits() { return this.lastEdit.size > 0; }

  /** Opens a Note with the text just read from disk, or just focuses it if it is already open. */
  open(path: string, diskText: string) {
    if (!this.texts.has(path)) {
      this.texts.set(path, diskText);
      this.onDisk.set(path, diskText);
      this.paths.push(path);
    }
    this.active = path;
  }

  edit(path: string, text: string, now = Date.now()) {
    if (!this.texts.has(path) || this.texts.get(path) === text) return;
    this.texts.set(path, text);
    this.lastEdit.set(path, now);
  }

  /** Notes to write now: last keystroke at least `AUTOSAVE_DELAY_MS` ago. Call `saved` after each write. */
  due(now = Date.now()): string[] {
    return this.pending().filter((p) => now - this.lastEdit.get(p)! >= AUTOSAVE_DELAY_MS);
  }

  /** Every unsaved Note without a conflict (quit, window close). */
  pending(): string[] {
    return [...this.lastEdit.keys()].filter((p) => !this.conflicts.has(p));
  }

  /** The write of `text` to `path` succeeded. Edits typed while it was in flight stay unsaved. */
  saved(path: string, text: string) {
    this.onDisk.set(path, text);
    if (this.texts.get(path) === text) this.lastEdit.delete(path);
  }

  /** FS watcher reported `path` changed; `diskText` is what is there now. Clean Notes reload silently, dirty ones conflict. */
  diskChanged(path: string, diskText: string) {
    if (!this.texts.has(path) || diskText === this.onDisk.get(path)) return;
    if (this.lastEdit.has(path)) this.conflicts.set(path, diskText);
    else this.adopt(path, diskText);
  }

  /** `reload`: take the disk text. Otherwise keep mine and return it, for the app to write over the disk text (then `saved`). */
  resolveConflict(path: string, reload: boolean): string | undefined {
    const disk = this.conflicts.get(path);
    if (disk === undefined) return;
    this.conflicts.delete(path);
    if (reload) return void this.adopt(path, disk);
    this.onDisk.set(path, disk);
    return this.texts.get(path);
  }

  /**
   * Closes the tab. A Note with a pending conflict stays open (closing would drop my edits or overwrite the disk
   * text). Returns the unsaved text for the app to write, if any.
   */
  close(path: string): { closed: boolean; flush?: string } {
    const i = this.paths.indexOf(path);
    if (i < 0 || this.conflicts.has(path)) return { closed: false };
    const flush = this.lastEdit.has(path) ? this.texts.get(path) : undefined;
    this.paths.splice(i, 1);
    for (const m of [this.texts, this.lastEdit, this.onDisk]) m.delete(path);
    if (this.active === path) this.active = this.paths[Math.min(i, this.paths.length - 1)] ?? null;
    return { closed: true, flush };
  }

  /** Replaces an open Note's text (edits included) with `diskText`; no-op if not open. */
  reload(path: string, diskText: string) {
    if (this.texts.has(path)) this.adopt(path, diskText);
  }

  private adopt(path: string, disk: string) {
    this.texts.set(path, disk);
    this.onDisk.set(path, disk);
    this.lastEdit.delete(path);
    this.conflicts.delete(path);
    this.revisions.set(path, this.revision(path) + 1);
  }
}
