"""MkDocs hook: merges data/*.yaml (one file per mapped repository) into graph.json for the System graph page."""
import json
import pathlib

import yaml


def on_post_build(config, **kwargs):
    data = pathlib.Path(config["config_file_path"]).parent / "data"
    repos = [yaml.safe_load(p.read_text(encoding="utf-8")) for p in sorted(data.glob("*.yaml"))]
    services = [dict(s, repo=r["repo"], commit=r["commit"]) for r in repos for s in r.get("services") or []]
    pathlib.Path(config["site_dir"], "graph.json").write_text(json.dumps(services), encoding="utf-8")
