# Known issues (QA round 5 on main @ e7c86f8, 2026-10-18)

Found by exploratory QA; not fixed yet. Fix work is split in two groups below (names refer to code areas). Script names in brackets (d1_unreadable etc.) refer to QA repro scripts kept outside the repo.
## Group 1: watcher, IPC and undo safety, unreadable Notes (shell lib.rs, core edit/vault/renames/index)
- M1: own-write echo (d8b_echo): in watch(), an outside change that doesn't match o.own[p] must clear that record, so a
  later change back to the saved text (git stash/pop, checkout A→B→A) is seen. Editor must show it; index must refresh.
- M2: apply_edits IPC (d3_ipc_link): FileEdits from the webview must not carry `link` or `mode` (refuse them, or ignore
  them and compute them in core). Any symlink target must pass safe_path; never apply setuid/setgid/sticky bits (mask mode to 0o777).
  Also check every other IPC command for raw fields that bypass core checks.
- M3: an open Note that becomes unreadable (non-UTF-8, mode 000) is treated as deleted (d1_unreadable). Show a distinct
  banner: "<path> can't be read (not UTF-8 / permission denied)". A clean tab keeps showing the last text read-only with that banner, not closed;
  never offer Re-create over an existing file.
- M4: undo keep-vs-drop must use a typed error kind from core (e.g. an enum: NotWritable vs ChangedSince vs Missing), not message
  substrings (d2_undo_class). Mode-000 target (nothing written) = keep; changed content = drop. Unit tests per kind.
- Minor 6: moving a symlinked Note with a relative link to another folder must write a RELATIVE link, recomputed for the new
  folder (never an absolute path with the machine's Vault path) (d4_moves).
- Minor 7: unreadable Notes: renaming a Note they link to must warn ("N Notes could not be read and still link to the old
  name"); renaming an unreadable Note must say why it can't; name search must list them (d1).
- Minor 8: renaming the target of a symlinked Note: warn that the alias will dangle (or refuse); never vanish silently (d4).
- Minor 9: recovery toast: once shown, offer "Open folder"/"Dismiss" and stop repeating after Dismiss (move dismissed files
  to .constellation/recovery/old/ or keep a seen list); if .constellation can't be written on a signal, try the Vault's parent temp
  (std::env::temp_dir()/constellation-recovery/) and log it, never lose text silently (d5_recovery).
- Minor 11: names: refuse Unicode bidi/format characters (U+200B–U+200F, U+202A–U+202E, U+2066–U+2069, U+2028/2029, U+FEFF) in New note/rename;
  rename_heading must refuse newlines/control chars (d6, d11_misc).
- Minor 13: .constellation/ shows as untracked in git: write `.constellation/.gitignore` containing `*` when creating the folder;
  write the cheat sheet only if its text differs (d8_git).
- Minor 14 (part): write_note must refuse non-.md paths (c3).
## Group 2: keyboard, accessibility, UI behaviour (ui/src/*, small core helpers if needed)
- M5 keyboard-only use (d9_a11y): make tree rows, search results, tabs and their ×, Tags rows, inspector rows and context-menu
  items focusable and operable:
  - roving tabindex + arrow keys in the tree and lists; Enter opens; Shift+F10 / the ContextMenu key opens the context menu; menu items are reachable with the arrows; Escape closes;
  - Ctrl+Tab / Ctrl+Shift+Tab switch tabs;
  - a key to follow the Link at the cursor (e.g. Ctrl/⌘+Enter);
  - focus trap in modals, with focus restored after close;
  - aria-labels on the search box and icon buttons; roles (tree, treeitem, tablist, tab, menu, menuitem).
  Document the new keys in the cheat sheet, and keep the shortcut-coverage test passing.
- Minor 10: [[#Heading]] jump must skip headings inside code fences (headingOffset); [[#Missing]] must show as broken (red) and a
  click must say the heading doesn't exist (d6_names).
- Minor 12: a drag-select starting on a Link must not open it: open on click (mouseup with no selection movement), not mousedown (d10_copy_tabs).
- Minor 14 (part): after the graph window is closed (window.close()), the Graph button / open_graph must reopen it (c9).
