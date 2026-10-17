import "./style.css";
import { boot } from "./app";
import { graphView } from "./graphView";

import { invoke } from "@tauri-apps/api/core";
const report = (m: string) => void invoke("log", { msg: m });
addEventListener("error", (e) => report(`${e.message} @${e.filename}:${e.lineno}`));
addEventListener("unhandledrejection", (e) => report(`unhandled: ${e.reason}`));
const app = document.getElementById("app")!;
void (new URLSearchParams(location.search).get("view") === "graph" ? graphView(app) : boot(app));
