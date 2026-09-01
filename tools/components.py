#!/usr/bin/env python3
"""Reads components.toml. The single place any tool learns what exists."""
import pathlib, sys, tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent

def load():
    with open(ROOT / "components.toml", "rb") as f:
        return tomllib.load(f)

def resolve(name, spec):
    return (ROOT / spec["path"]).resolve()

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "list"
    comps = load()
    for name, spec in comps.items():
        p = resolve(name, spec)
        if what == "list":
            mark = " " if p.is_dir() else "?"
            print(f"{mark} {name:10} {spec['role']:10} {p}")
        elif what == "paths":
            print(p)
        elif what == "names":
            print(name)
        elif what == "test":
            if spec.get("test"):
                print(f"{name}\t{p}\t{spec['test']}")
