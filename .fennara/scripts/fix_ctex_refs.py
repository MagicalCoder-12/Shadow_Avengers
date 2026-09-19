"""Convert inline CompressedTexture2D sub_resources (stale .godot/imported hashes)
to stable ext_resource references in scene files.

These inline load_path sub_resources embed an import hash that changes whenever
import settings change, breaking scenes at runtime. Replacing them with plain
ext_resource Texture2D references makes scenes hash-independent.

NOTE: removal of K sub_resources and insertion of K ext_resources keeps the
scene's load_steps count unchanged.
"""
import os
import re
import sys

ROOT = "."

def find_png(name: str) -> str:
    """Find a source png by basename under res:// (excluding build dirs)."""
    hits = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (
            ".git", ".godot", "android", "Apks", "_archive", ".fennara",
            ".qoder", ".vscode", ".freebuff", "docs", ".github", ".tools")]
        if name in filenames:
            hits.append("res://" + os.path.join(dirpath, name).replace(os.sep, "/").lstrip("./"))
    if len(hits) != 1:
        print(f"  !! {name}: {len(hits)} candidates {hits}", file=sys.stderr)
        return ""
    return hits[0]

def fix_scene(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    out = []
    sub_ids = {}   # sub_resource id -> (png basename, ext id)
    i = 0
    # Pass 1: strip sub_resource CompressedTexture2D blocks with load_path
    while i < len(lines):
        line = lines[i]
        m = re.match(r'\[sub_resource type="CompressedTexture2D" id="([^"]+)"\]', line)
        if m and i + 1 < len(lines) and "load_path = " in lines[i + 1]:
            sub_id = m.group(1)
            lp = re.search(
                r'load_path = "res://\.godot/imported/([^"]+\.png)-[0-9a-f]+\.ctex"',
                lines[i + 1])
            if lp:
                png = lp.group(1)
                ext_id = "tex_" + re.sub(r"[^A-Za-z0-9_]", "_", png.replace(".png", ""))
                sub_ids[sub_id] = (png, ext_id)
                i += 2
                if i < len(lines) and lines[i].strip() == "":
                    i += 1
                continue
        out.append(line)
        i += 1
    if not sub_ids:
        return 0
    txt = "".join(out)
    # Pass 2: resolve source paths BEFORE any edits, fail loudly if ambiguous
    decls = []
    for sub_id, (png, ext_id) in sub_ids.items():
        res_path = find_png(png)
        if not res_path:
            print(f"  !! could not resolve {png} in {path}", file=sys.stderr)
            return 0
        decls.append(f'[ext_resource type="Texture2D" path="{res_path}" id="{ext_id}"]\n')
    # Pass 3: swap SubResource uses for ExtResource uses
    for sub_id, (png, ext_id) in sub_ids.items():
        txt = txt.replace(f'SubResource("{sub_id}")', f'ExtResource("{ext_id}")')
    # Pass 4: insert ext_resource declarations after the last existing one
    matches = list(re.finditer(r'\[ext_resource [^\n]*\]\n', txt))
    if not matches:
        print(f"  !! no ext_resource section in {path}", file=sys.stderr)
        return 0
    last = matches[-1]
    txt = txt[:last.end()] + "".join(decls) + txt[last.end():]
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(txt)
    return len(sub_ids)

def main() -> None:
    scenes = [
        "Bullet/PlBullet/super2.tscn",
        "Enemy/bouncer_enemy.tscn",
        "Enemy/fast_enemy.tscn",
        "Map/map.tscn",
        "Powerups/SuperMode.tscn",
        "Satellites/Satellite2.tscn",
        "Ships/Player_Ship3.tscn",
    ]
    total = 0
    for s in scenes:
        n = fix_scene(s)
        total += n
        print(f"{s}: {n} texture ref(s) converted")
    print(f"TOTAL: {total}")

if __name__ == "__main__":
    main()
