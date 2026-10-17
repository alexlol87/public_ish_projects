import { invoke } from "@tauri-apps/api/core";

export interface Range16 { location: number; length: number }
export interface VaultNode { name: string; relativePath: string; isFolder: boolean; children: VaultNode[]; appOnly: boolean }
export interface TextMatch { path: string; sentence: string; hit: Range16; offset: number }
export interface SearchResults { folders: string[]; notes: string[]; matches: TextMatch[]; archived: string[] }
export interface TagNode { tag: string; name: string; count: number; children: TagNode[] }
export interface TagHit { path: string; line: string; offset: number }
export interface Heading { level: number; title: string; range: Range16 }
export interface Backlink { path: string; link: { range: Range16; target: string; heading?: string; alias?: string } }
export interface EndpointRef { path: string; heading?: string }
export interface Relations { callsOut: EndpointRef[]; callsIn: EndpointRef[]; usesIn: EndpointRef[] }
export interface RepoInfo { folder: string; name: string; label: string; stale: boolean }
export interface Inspect { headings: Heading[]; endpoint?: string; relations?: Relations; backlinks: Backlink[]; repo?: RepoInfo }
export type EdgeKind = "containment" | "link" | "call" | "uses";
export interface GraphNode { id: string; name: string; kind: "note" | "folder" | "ghost"; noteType?: string; tags: string[] }
export interface GraphEdge { from: string; to: string; kind: EdgeKind; pairs: { from: string; to: string }[] }
export interface VaultGraph { nodes: GraphNode[]; edges: GraphEdge[] }
export interface GraphFilter { projects: string[]; types: string[]; edgeKinds: EdgeKind[]; tag?: string | null; includeArchive: boolean; localDepth: number }
export interface Settings { theme: string; stalenessDays: number }
export type Resolution = { kind: "note"; path: string } | { kind: "broken"; createPath: string };
export interface ChangeEvent { paths: string[]; own: boolean }

export const api = {
  startup: () => invoke<string | null>("startup"),
  openVault: (path: string) => invoke<string>("open_vault", { path }),
  createVault: (path: string) => invoke<string>("create_vault", { path }),
  pickFolder: () => invoke<string | null>("pick_folder"),
  copyText: (text: string) => invoke<void>("copy_text", { text }),
  getSettings: () => invoke<Settings>("get_settings"),
  setSettings: (settings: Settings) => invoke<void>("set_settings", { settings }),
  tree: () => invoke<VaultNode>("tree"),
  readNote: (path: string) => invoke<string>("read_note", { path }),
  writeNote: (path: string, text: string) => invoke<void>("write_note", { path, text }),
  search: (query: string) => invoke<SearchResults>("search", { query }),
  tagTree: (sort: "name" | "count") => invoke<TagNode[]>("tag_tree", { sort }),
  tagHits: (tag: string) => invoke<TagHit[]>("tag_hits", { tag }),
  tagCompletions: (prefix: string) => invoke<string[]>("tag_completions", { prefix }),
  linkCompletions: (typed: string) => invoke<string[]>("link_completions", { typed }),
  resolve: (target: string) => invoke<Resolution>("resolve", { target }),
  brokenTargets: (text: string) => invoke<string[]>("broken_targets", { text }),
  inspect: (path: string, text: string, offset: number) => invoke<Inspect>("inspect", { path, text, offset }),
  prompt: (kind: "ingest" | "refresh", repo: string) => invoke<string>("prompt", { kind, repo }),
  graph: (filter: GraphFilter, around: string | null) => invoke<VaultGraph>("graph", { filter, around }),
  graphFilter: () => invoke<GraphFilter>("graph_filter"),
  saveGraphFilter: (filter: GraphFilter) => invoke<void>("save_graph_filter", { filter }),
  setCurrent: (path: string | null) => invoke<void>("set_current", { path }),
  getCurrent: () => invoke<string | null>("get_current"),
  openGraph: () => invoke<void>("open_graph"),
  showNote: (path: string) => invoke<void>("show_note", { path }),
  undo: () => invoke<boolean>("undo"),
  undoDepth: () => invoke<number>("undo_depth"),
  createNote: (target: string) => invoke<string>("create_note", { target }),
  renameNote: (path: string, newPath: string) => invoke<string>("rename_note", { path, newPath }),
  renameHeading: (path: string, old: string, newTitle: string) => invoke<void>("rename_heading", { path, old, new: newTitle }),
  renameTag: (old: string, newName: string) => invoke<void>("rename_tag", { old, new: newName }),
  tick: (path: string, text: string, offset: number) => invoke<string[]>("tick", { path, text, offset }),
};

/** "a/b/c.md" -> "c" */
export const baseName = (p: string) => (p.split("/").pop() ?? p).replace(/\.md$/i, "");
export const errText = (e: unknown) => (typeof e === "string" ? e : e instanceof Error ? e.message : JSON.stringify(e));
