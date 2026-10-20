import type { TFile } from "obsidian";
import type ConstellationPlugin from "./main.ts";

/** Repo section of the panel (ticket 03). Leave `el` empty when the file is not in a Repo. */
export function renderRepoSection(el: HTMLElement, plugin: ConstellationPlugin, file: TFile) {}
