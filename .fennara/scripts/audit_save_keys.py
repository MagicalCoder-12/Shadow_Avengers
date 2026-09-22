"""Audit save/tutorial keys that are read but never written.

A key the code reads but nothing ever writes silently disables the guard it
feeds, because .get(key, default) always falls back to the default. Two such
bugs already shipped: the satellite migration's `purchased` marker and the
satellite `level` field.

Usage:  python .fennara/scripts/audit_save_keys.py
Exit code 1 when a dead save key is found, so it can gate a check.
"""
import json
import os
import re
import sys
import collections

SKIP_DIRS = {".godot", ".git", ".fennara", ".freebuff", "addons"}

# Reads with no writer that are known to be benign: the game carries an
# equivalent fallback, so the visible behaviour is already correct. Each entry
# must name that fallback, so the list cannot quietly hide a real defect.
BENIGN_WITH_FALLBACK = {}

# Containers that hold persisted / tutorial data (and the config tables that
# feed them), so only keys the save system cares about are reported.
SAVEISH = re.compile(
    r"(payload|progress_data|player_data|resources_data|wheel_data|ads_data|"
    r"tutorial_data|tutorial_state|satellite|satellites|ship|ships|item|"
    r"upgrade_settings|save_data)"
)

GET = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\.get\(\s*"([A-Za-z0-9_]+)"')
HAS = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\.has\(\s*"([A-Za-z0-9_]+)"')
ASSIGN = re.compile(r'\[\s*"([A-Za-z0-9_]+)"\s*\]\s*=')
LITERAL = re.compile(r'"([A-Za-z0-9_]+)"\s*:')


def json_keys():
    """Keys provided by the JSON config tables (they are writers too)."""
    keys = set()
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if not name.endswith(".json"):
                continue
            try:
                data = json.load(open(os.path.join(root, name), encoding="utf-8"))
            except (OSError, ValueError):
                continue
            keys.update(_walk_keys(data))
    return keys


def _walk_keys(node):
    if isinstance(node, dict):
        for key, value in node.items():
            yield key
            yield from _walk_keys(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_keys(item)


def gd_files():
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name.endswith(".gd"):
                yield os.path.join(root, name)


def main() -> int:
    reads = collections.defaultdict(set)
    writes = set()
    for path in gd_files():
        src = open(path, encoding="utf-8", errors="replace").read()
        for owner, key in GET.findall(src) + HAS.findall(src):
            if SAVEISH.search(owner):
                reads[key].add(path.replace("./", ""))
        writes.update(ASSIGN.findall(src))
        writes.update(LITERAL.findall(src))
    writes.update(json_keys())

    dead = {k: v for k, v in reads.items() if k not in writes}
    benign = {k: v for k, v in dead.items() if k in BENIGN_WITH_FALLBACK}
    dead = {k: v for k, v in dead.items() if k not in BENIGN_WITH_FALLBACK}

    for key in sorted(benign):
        print("benign (code fallback): %-24s read by: %s" % (key, ", ".join(sorted(benign[key]))))

    if not dead:
        print("OK: every save/tutorial key that is read also has a writer.")
        return 0

    print("READ-BUT-NEVER-WRITTEN SAVE KEYS (%d):" % len(dead))
    for key in sorted(dead):
        print("  %-26s read by: %s" % (key, ", ".join(sorted(dead[key]))))
    return 1


if __name__ == "__main__":
    sys.exit(main())
