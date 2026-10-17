//! Tauri shell around `constellation-core`: one open Vault in a `Mutex`, a file watcher, and thin commands.
//! Events: `vault-changed {paths, own}` (own = written by this app's save, so open tabs need no disk check),
//! `current-note {path}` (main window's active Note, for the graph window), `open-note {path}` (graph -> main).

use constellation_core::graph::{GraphFilter, VaultGraph};
use constellation_core::{agent_files, archiver, edit, parser, renames, search, staleness, tags, vault};
use constellation_core::{Backlink, EndpointRelations, Error, FileEdit, LinkResolution, VaultIndex, VaultNode};
use notify_debouncer_mini::{new_debouncer, notify::RecommendedWatcher, notify::RecursiveMode, Debouncer};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;

type Res<T> = Result<T, Error>;

struct Open {
    index: VaultIndex,
    /// Inverse edits of each user action, newest last.
    undo: Vec<Vec<FileEdit>>,
    /// What this app last wrote per path (None = deleted); the watcher skips echoes of these.
    own: HashMap<String, Option<String>>,
    _watcher: Debouncer<RecommendedWatcher>,
}

#[derive(Default)]
struct AppState {
    vault: Mutex<Option<Open>>,
    current: Mutex<Option<String>>,
}

fn err(e: impl std::fmt::Display) -> Error {
    Error(e.to_string())
}

fn with<T>(st: &AppState, f: impl FnOnce(&mut Open) -> Res<T>) -> Res<T> {
    let mut g = st.vault.lock().map_err(err)?;
    f(g.as_mut().ok_or_else(|| Error("No vault is open".into()))?)
}

// ---- config: theme in the app config dir, staleness days in the Vault's .constellation/ ----

#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Config {
    last_vault: Option<String>,
    theme: Option<String>,
}

fn config_file(app: &AppHandle) -> Res<PathBuf> {
    Ok(app.path().app_config_dir().map_err(err)?.join("config.json"))
}

fn load_config(app: &AppHandle) -> Config {
    config_file(app).ok().and_then(|f| std::fs::read(f).ok()).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn save_config(app: &AppHandle, c: &Config) -> Res<()> {
    vault::write_atomic(&config_file(app)?, &serde_json::to_string(c).map_err(err)?)
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Settings {
    theme: String,
    staleness_days: i64,
}

fn staleness_days(root: &Path) -> i64 {
    std::fs::read(root.join(".constellation/settings.json"))
        .ok()
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .and_then(|v| v["stalenessDays"].as_i64())
        .unwrap_or(staleness::DEFAULT_THRESHOLD)
}

#[tauri::command]
fn get_settings(app: AppHandle, st: State<AppState>) -> Settings {
    let days =
        st.vault.lock().ok().and_then(|g| g.as_ref().map(|o| staleness_days(o.index.root()))).unwrap_or(staleness::DEFAULT_THRESHOLD);
    Settings { theme: load_config(&app).theme.unwrap_or_else(|| "System".into()), staleness_days: days }
}

#[tauri::command]
fn set_settings(app: AppHandle, st: State<AppState>, settings: Settings) -> Res<()> {
    let mut c = load_config(&app);
    c.theme = Some(settings.theme);
    save_config(&app, &c)?;
    if let Some(o) = st.vault.lock().map_err(err)?.as_ref() {
        let json = serde_json::json!({ "stalenessDays": settings.staleness_days.max(1) }).to_string();
        vault::write_atomic(&o.index.root().join(".constellation/settings.json"), &json)?;
    }
    Ok(())
}

// ---- opening a Vault and watching it ----

fn emit_changed(app: &AppHandle, paths: &[String], own: bool) {
    let _ = app.emit("vault-changed", serde_json::json!({ "paths": paths, "own": own }));
}

/// Records what we wrote at `paths`, re-indexes them and tells the windows.
fn finish(app: &AppHandle, o: &mut Open, paths: Vec<String>, own: bool) -> Res<()> {
    for p in &paths {
        o.own.insert(p.clone(), std::fs::read_to_string(o.index.root().join(p)).ok());
    }
    o.index.ingest(&paths)?;
    emit_changed(app, &paths, own);
    Ok(())
}

fn watch(app: &AppHandle, root: &Path) -> Res<Debouncer<RecommendedWatcher>> {
    let handle = app.clone();
    let base = root.to_path_buf();
    let mut deb = new_debouncer(Duration::from_millis(300), move |res: notify_debouncer_mini::DebounceEventResult| {
        let Ok(events) = res else { return };
        let mut paths: Vec<String> = events
            .iter()
            .filter_map(|e| e.path.strip_prefix(&base).ok())
            .map(|p| p.components().map(|c| c.as_os_str().to_string_lossy().into_owned()).collect::<Vec<_>>().join("/"))
            // Hidden files and our atomic-write temp files are not Notes; `.constellation` shows in the tree.
            .filter(|p| !p.is_empty() && !p.ends_with(".tmp"))
            .filter(|p| p.split('/').enumerate().all(|(i, s)| !s.starts_with('.') || (i == 0 && s == ".constellation")))
            .collect();
        paths.sort();
        paths.dedup();
        let st = handle.state::<AppState>();
        let Ok(mut g) = st.vault.lock() else { return };
        let Some(o) = g.as_mut().filter(|o| o.index.root() == base) else { return };
        paths.retain(|p| {
            let now = std::fs::read_to_string(base.join(p)).ok();
            // An echo of our own write: same content as we left it.
            !(o.own.get(p).is_some_and(|w| *w == now) && o.own.remove(p).is_some())
        });
        if paths.is_empty() || o.index.ingest(&paths).is_err() {
            return;
        }
        emit_changed(&handle, &paths, false);
    })
    .map_err(err)?;
    deb.watcher().watch(root, RecursiveMode::Recursive).map_err(err)?;
    Ok(deb)
}

fn open_at(app: &AppHandle, st: &AppState, path: &Path) -> Res<String> {
    let root = path.canonicalize()?;
    let index = VaultIndex::open(&root)?;
    let _watcher = watch(app, &root)?;
    *st.vault.lock().map_err(err)? = Some(Open { index, undo: vec![], own: HashMap::new(), _watcher });
    let s = root.to_string_lossy().into_owned();
    let mut c = load_config(app);
    c.last_vault = Some(s.clone());
    let _ = save_config(app, &c);
    Ok(s)
}

#[tauri::command]
fn startup(app: AppHandle, st: State<AppState>) -> Option<String> {
    let env = std::env::var("CONSTELLATION_VAULT").ok().filter(|s| !s.is_empty());
    let path = env.map(PathBuf::from).or_else(|| vault::reopenable(load_config(&app).last_vault.as_deref()))?;
    open_at(&app, &st, &path).ok()
}

#[tauri::command]
fn open_vault(app: AppHandle, st: State<AppState>, path: String) -> Res<String> {
    open_at(&app, &st, Path::new(&path))
}

#[tauri::command]
fn create_vault(app: AppHandle, st: State<AppState>, path: String) -> Res<String> {
    vault::create(Path::new(&path))?;
    open_at(&app, &st, Path::new(&path))
}

#[tauri::command]
async fn pick_folder(app: AppHandle) -> Option<String> {
    // e2e harness only: a native dialog can't be driven by WebDriver, so it names the answer here.
    if let Some(dir) = std::env::var("CONSTELLATION_E2E_PICK").ok().filter(|s| !s.is_empty()) {
        return Some(dir);
    }
    app.dialog().file().blocking_pick_folder().and_then(|p| p.into_path().ok()).map(|p| p.to_string_lossy().into_owned())
}

#[tauri::command]
fn copy_text(app: AppHandle, text: String) -> Res<()> {
    app.clipboard().write_text(text).map_err(err)
}

// ---- reading ----

#[tauri::command]
fn tree(st: State<AppState>) -> Res<VaultNode> {
    with(&st, |o| Ok(o.index.tree().clone()))
}

#[tauri::command]
fn read_note(st: State<AppState>, path: String) -> Res<String> {
    with(&st, |o| vault::read_note(o.index.root(), &path))
}

#[tauri::command]
fn write_note(app: AppHandle, st: State<AppState>, path: String, text: String) -> Res<()> {
    with(&st, |o| {
        vault::write_note(o.index.root(), &path, &text)?;
        finish(&app, o, vec![path], true)
    })
}

#[tauri::command]
fn search(st: State<AppState>, query: String) -> Res<search::Results> {
    with(&st, |o| Ok(o.index.search(&query)))
}

#[tauri::command]
fn tag_tree(st: State<AppState>, sort: tags::Sort) -> Res<Vec<tags::Node>> {
    with(&st, |o| Ok(o.index.tag_tree(sort)))
}

#[tauri::command]
fn tag_hits(st: State<AppState>, tag: String) -> Res<Vec<tags::Hit>> {
    with(&st, |o| Ok(o.index.tag_hits(&tag)))
}

#[tauri::command]
fn tag_completions(st: State<AppState>, prefix: String) -> Res<Vec<String>> {
    with(&st, |o| Ok(o.index.tag_completions(&prefix)))
}

#[tauri::command]
fn link_completions(st: State<AppState>, typed: String) -> Res<Vec<String>> {
    with(&st, |o| Ok(o.index.completions(&typed)))
}

#[tauri::command]
fn resolve(st: State<AppState>, target: String) -> Res<LinkResolution> {
    with(&st, |o| Ok(o.index.resolve(&target)))
}

/// Targets (without `#heading`) of the Links in `text` that do not resolve.
#[tauri::command]
fn broken_targets(st: State<AppState>, text: String) -> Res<Vec<String>> {
    with(&st, |o| Ok(o.index.broken_links(&text).into_iter().map(|l| l.target).collect()))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RepoInfo {
    folder: String,
    name: String,
    label: String,
    stale: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Inspect {
    headings: Vec<parser::NoteHeading>,
    endpoint: Option<String>,
    relations: Option<EndpointRelations>,
    backlinks: Vec<Backlink>,
    repo: Option<RepoInfo>,
}

/// Everything the right pane shows for the Note `path` whose current text is `text`, cursor at UTF-16 `offset`.
#[tauri::command]
fn inspect(st: State<AppState>, path: String, text: String, offset: usize) -> Res<Inspect> {
    with(&st, |o| {
        let note = parser::parse(&text);
        let endpoint = note.endpoint_heading(offset).map(|h| h.title.clone());
        let relations = endpoint.as_ref().map(|h| o.index.endpoint_relations(&path, h));
        // A Repo is `<project>/<repo>/`: only Notes at least that deep belong to one.
        let folder = path.split('/').take(2).collect::<Vec<_>>().join("/");
        let repo = (path.matches('/').count() >= 2 && agent_files::is_repo_folder(&folder)).then(|| {
            let s = o.index.repo_staleness(staleness::today()).get(&folder).copied();
            let days = staleness_days(o.index.root());
            RepoInfo {
                name: folder.rsplit('/').next().unwrap_or("").into(),
                label: s.map(|s| s.label()).unwrap_or_else(|| "no repo README".into()),
                stale: s.is_none_or(|s| s.is_stale(days)),
                folder,
            }
        });
        Ok(Inspect { headings: note.headings, endpoint, relations, backlinks: o.index.backlinks(&path), repo })
    })
}

/// Frontend errors end up on stderr, which is all a headless run can see.
#[tauri::command]
fn log(msg: String) {
    eprintln!("[ui] {msg}");
}

#[tauri::command]
fn prompt(kind: String, repo: String) -> String {
    if kind == "ingest" {
        agent_files::ingest_prompt(&repo)
    } else {
        agent_files::refresh_prompt(&repo)
    }
}

// ---- graph ----

#[tauri::command]
fn graph(st: State<AppState>, filter: GraphFilter, around: Option<String>) -> Res<VaultGraph> {
    with(&st, |o| Ok(o.index.graph(&filter, around.as_deref())))
}

#[tauri::command]
fn graph_filter(st: State<AppState>) -> Res<GraphFilter> {
    with(&st, |o| Ok(GraphFilter::load(o.index.root())))
}

#[tauri::command]
fn save_graph_filter(st: State<AppState>, filter: GraphFilter) -> Res<()> {
    with(&st, |o| filter.save(o.index.root()))
}

#[tauri::command]
fn set_current(app: AppHandle, st: State<AppState>, path: Option<String>) {
    *st.current.lock().unwrap() = path.clone();
    let _ = app.emit("current-note", path);
}

#[tauri::command]
fn get_current(st: State<AppState>) -> Option<String> {
    st.current.lock().unwrap().clone()
}

#[tauri::command]
async fn open_graph(app: AppHandle) -> Res<()> {
    if let Some(w) = app.get_webview_window("graph") {
        return w.set_focus().map_err(err);
    }
    WebviewWindowBuilder::new(&app, "graph", WebviewUrl::App("index.html?view=graph".into()))
        .title("Constellation graph")
        .inner_size(1000.0, 750.0)
        .build()
        .map_err(err)?;
    Ok(())
}

/// Graph window -> main window: open this Note.
#[tauri::command]
fn show_note(app: AppHandle, path: String) {
    let _ = app.emit("open-note", path);
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_focus();
    }
}

// ---- edits (one undo step per call) ----

fn apply(app: &AppHandle, o: &mut Open, edits: Vec<FileEdit>) -> Res<Vec<String>> {
    if edits.is_empty() {
        return Ok(vec![]);
    }
    let inverse = edit::apply(&edits, o.index.root());
    let mut paths: Vec<String> = edits.iter().map(|e| e.path.clone()).collect();
    paths.sort();
    paths.dedup();
    // Even a failed batch may have written some files: re-index them.
    let inverse = match inverse {
        Ok(i) => i,
        Err(e) => {
            finish(app, o, paths, false)?;
            return Err(e);
        }
    };
    o.undo.push(inverse);
    finish(app, o, paths.clone(), false)?;
    Ok(paths)
}

/// Applies `edits`; returns the touched paths.
#[tauri::command]
fn apply_edits(app: AppHandle, st: State<AppState>, edits: Vec<FileEdit>) -> Res<Vec<String>> {
    with(&st, |o| apply(&app, o, edits))
}

#[tauri::command]
fn undo(app: AppHandle, st: State<AppState>) -> Res<bool> {
    with(&st, |o| {
        let Some(inverse) = o.undo.pop() else { return Ok(false) };
        let mut paths: Vec<String> = inverse.iter().map(|e| e.path.clone()).collect();
        paths.sort();
        paths.dedup();
        let r = edit::apply(&inverse, o.index.root());
        finish(&app, o, paths, false)?;
        r.map(|_| true)
    })
}

#[tauri::command]
fn undo_depth(st: State<AppState>) -> usize {
    st.vault.lock().ok().and_then(|g| g.as_ref().map(|o| o.undo.len())).unwrap_or(0)
}

/// Creates the Note a broken Link points to; returns its path.
#[tauri::command]
fn create_note(app: AppHandle, st: State<AppState>, target: String) -> Res<String> {
    with(&st, |o| {
        let edits = o.index.create_note_edits(&target);
        let path = edits.first().map(|e| e.path.clone());
        apply(&app, o, edits)?;
        path.ok_or_else(|| Error("The link already resolves".into()))
    })
}

/// Renames a Note (same folder) or moves it to another folder (same name); rewrites Links.
#[tauri::command]
fn rename_note(app: AppHandle, st: State<AppState>, path: String, new_path: String) -> Res<String> {
    with(&st, |o| {
        let (old_dir, old_name) = path.rsplit_once('/').unwrap_or(("", &path));
        let (new_dir, new_name) = new_path.trim_matches('/').rsplit_once('/').unwrap_or(("", new_path.trim_matches('/')));
        let edits = if old_dir == new_dir {
            renames::rename_note(&o.index, &path, new_name)?
        } else if old_name == new_name || format!("{new_name}.md") == old_name {
            renames::move_note_to_folder(&o.index, &path, new_dir)?
        } else {
            return Err(Error("Rename or move, not both at once".into()));
        };
        apply(&app, o, edits)?;
        let file = if old_dir == new_dir { format!("{}{}", new_name.trim_end_matches(".md"), ".md") } else { old_name.to_string() };
        Ok(if new_dir.is_empty() { file } else { format!("{new_dir}/{file}") })
    })
}

#[tauri::command]
fn rename_heading(app: AppHandle, st: State<AppState>, path: String, old: String, new: String) -> Res<()> {
    with(&st, |o| {
        let edits = renames::rename_heading(&o.index, &old, &new, &path)?;
        apply(&app, o, edits).map(drop)
    })
}

#[tauri::command]
fn rename_tag(app: AppHandle, st: State<AppState>, old: String, new: String) -> Res<()> {
    with(&st, |o| {
        let edits = renames::rename_tag(&o.index, &old, &new)?;
        apply(&app, o, edits).map(drop)
    })
}

/// A click on a task box in `text` (the saved buffer of `path`) at UTF-16 `offset`.
#[tauri::command]
fn tick(app: AppHandle, st: State<AppState>, path: String, text: String, offset: usize) -> Res<Vec<String>> {
    with(&st, |o| {
        let edits = archiver::tick(&o.index, offset, &text, &path, staleness::today())?;
        apply(&app, o, edits)
    })
}

// ---- images: vaultimg://localhost/?note=..&path=.. ----

fn image_response(app: &AppHandle, uri: &str) -> Option<tauri::http::Response<Vec<u8>>> {
    let url = tauri::Url::parse(uri).ok()?;
    let q: HashMap<_, _> = url.query_pairs().collect();
    let st = app.state::<AppState>();
    let g = st.vault.lock().ok()?;
    let file = vault::resolve_image(q.get("path")?, q.get("note")?, g.as_ref()?.index.root())?;
    let mime = match file.extension()?.to_str()?.to_lowercase().as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        _ => return None,
    };
    tauri::http::Response::builder().header("Content-Type", mime).body(std::fs::read(file).ok()?).ok()
}

pub fn run() {
    // Blank/black windows in VMs and on some GPUs come from WebKitGTK's DMABUF renderer.
    #[cfg(target_os = "linux")]
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(AppState::default())
        // The graph window must not keep the app alive after the main window is gone.
        .on_window_event(|w, ev| {
            if w.label() == "main" && matches!(ev, tauri::WindowEvent::Destroyed) {
                w.app_handle().exit(0);
            }
        })
        .register_uri_scheme_protocol("vaultimg", |ctx, req| {
            image_response(ctx.app_handle(), &req.uri().to_string())
                .unwrap_or_else(|| tauri::http::Response::builder().status(404).body(vec![]).unwrap())
        })
        .invoke_handler(tauri::generate_handler![
            log,
            get_settings,
            set_settings,
            startup,
            open_vault,
            create_vault,
            pick_folder,
            copy_text,
            tree,
            read_note,
            write_note,
            search,
            tag_tree,
            tag_hits,
            tag_completions,
            link_completions,
            resolve,
            broken_targets,
            inspect,
            prompt,
            graph,
            graph_filter,
            save_graph_filter,
            set_current,
            get_current,
            open_graph,
            show_note,
            apply_edits,
            undo,
            undo_depth,
            create_note,
            rename_note,
            rename_heading,
            rename_tag,
            tick
        ])
        .run(tauri::generate_context!())
        .expect("error while running Constellation");
}
