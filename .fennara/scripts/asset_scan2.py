import os, re, shutil

static_refs = set()
uid_refs = set()
loadpath_names = set()  # basenames referenced via inline load_path
ctex_map = {}  # res://.godot/imported/xxx.ctex -> res://source.png

# Pass 1: collect all text refs
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'addons', '.fennara', 'android', 'Apks', '.qoder', '.vscode', '.freebuff', '_archive')]
    for fn in files:
        if not fn.endswith(('.tscn', '.tres', '.gd', '.json', '.cfg', '.gdshader', '.import')):
            continue
        p = os.path.join(root, fn)
        if fn.endswith('.import'):
            itxt = open(p, encoding='utf-8', errors='ignore').read()
            mu = re.search(r'uid="(uid://[a-z0-9]+)"', itxt)
            for m in re.finditer(r'(?:dest_files/path)="(res://[^"]+)"', itxt):
                dest = m.group(1)
                if dest.endswith(('.ctex', '.sample', '.oggvorbisstr', '.res')):
                    src = 'res://' + os.path.join(root, fn).replace(os.sep, '/').lstrip('./')[:-7]
                    ctex_map[dest] = src
            continue
        txt = open(p, encoding='utf-8', errors='ignore').read()
        rel = 'res://' + os.path.join(root, fn).replace(os.sep, '/').lstrip('./')
        for m in re.finditer(r'"?(res://[^"\s]+)"?', txt):
            v = m.group(1)
            static_refs.add(v)
            if v in ctex_map:
                static_refs.add(ctex_map[v])
        # inline CompressedTexture2D sub-resources reference imported textures
        # via load_path = "res://.godot/imported/<name>-<hash>.ctex"
        for m in re.finditer(r'load_path = "res://\.godot/imported/([^-]+)-[a-f0-9]+\.', txt):
            loadpath_names.add(m.group(1))
        for m in re.finditer(r'"(uid://[a-z0-9]+)"', txt):
            uid_refs.add(m.group(1))

# project.godot: quoted paths (incl. boot splash, cursor, theme)
proj = open('project.godot', encoding='utf-8').read()
for m in re.finditer(r'"?(res://[^"\s]+)"?', proj):
    v = m.group(1)
    static_refs.add(v)
    if v in ctex_map:
        static_refs.add(ctex_map[v])

# asset uid map
asset_uids = {}
asset_files = []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'addons', '.fennara', 'android', 'Apks', '.qoder', '.vscode', '.freebuff', '_archive')]
    for fn in files:
        if not fn.endswith(('.png', '.jpg', '.jpeg', '.webp', '.svg', '.wav', '.ogg', '.mp3', '.ttf', '.otf')):
            continue
        p = os.path.join(root, fn).replace(os.sep, '/').lstrip('./')
        asset_files.append(p)
        imp = p + '.import'
        if os.path.exists(imp):
            mu = re.search(r'uid="(uid://[a-z0-9]+)"', open(imp, encoding='utf-8', errors='ignore').read())
            if mu:
                asset_uids[p] = mu.group(1)

orphans = []
for p in asset_files:
    res = 'res://' + p
    if res in static_refs:
        continue
    if os.path.basename(p) in loadpath_names:
        continue
    u = asset_uids.get(p)
    if u and u in uid_refs:
        continue
    orphans.append(p)

print("load_path-referenced names:", len(loadpath_names))
print("TOTAL ASSETS:", len(asset_files))
print("TRUE ORPHANS:", len(orphans))
by_dir = {}
for p in orphans:
    d = '/'.join(p.split('/')[:2])
    by_dir.setdefault(d, []).append(p)
for d in sorted(by_dir):
    print(f"  {d}: {len(by_dir[d])}")

with open('.fennara/state/orphan_assets.txt', 'w') as f:
    f.write('\n'.join(sorted(orphans)))
print("list saved to .fennara/state/orphan_assets.txt")
