import os, re

static_refs = set()
uid_refs = set()
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'addons', '.fennara', 'android', 'Apks', '.qoder', '.vscode', '.freebuff')]
    for fn in files:
        if not fn.endswith(('.tscn', '.tres', '.gd', '.json', '.cfg', '.gdshader')):
            continue
        txt = open(os.path.join(root, fn), encoding='utf-8', errors='ignore').read()
        for m in re.finditer(r'path="(res://[^"]+)"', txt):
            static_refs.add(m.group(1))
        for m in re.finditer(r'"(uid://[a-z0-9]+)"', txt):
            uid_refs.add(m.group(1))
        for m in re.finditer(r'(?:preload|load)\(["\']([^"\')]+)["\']\)', txt):
            static_refs.add(m.group(1))
        # uid="..." attribute form (ext_resource in scenes already covered by path=, uid refs in gd covered)

proj = open('project.godot', encoding='utf-8').read()
for m in re.finditer(r'autoload/\w+="\*?(res://[^"]+)"', proj):
    static_refs.add(m.group(1))
for m in re.finditer(r'=(res://[^"\n]+)', proj):
    static_refs.add(m.group(1).rstrip())

# asset -> uid map from .import files
asset_uids = {}
asset_files = []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'addons', '.fennara', 'android', 'Apks', '.qoder', '.vscode', '.freebuff')]
    for fn in files:
        if not fn.endswith(('.png', '.jpg', '.jpeg', '.webp', '.svg', '.wav', '.ogg', '.mp3', '.ttf', '.otf')):
            continue
        p = os.path.join(root, fn).replace(os.sep, '/').lstrip('./')
        asset_files.append(p)
        imp = p + '.import'
        if os.path.exists(imp):
            itxt = open(imp, encoding='utf-8', errors='ignore').read()
            mu = re.search(r'uid="(uid://[a-z0-9]+)"', itxt)
            if mu:
                asset_uids[p] = mu.group(1)

orphans = []
for p in asset_files:
    res = 'res://' + p
    if res in static_refs:
        continue
    u = asset_uids.get(p)
    if u and u in uid_refs:
        continue
    orphans.append(p)

print("TOTAL ASSETS:", len(asset_files))
print("ORPHAN ASSETS:", len(orphans))
by_dir = {}
for p in orphans:
    d = '/'.join(p.split('/')[:2])
    by_dir.setdefault(d, []).append(p)
for d in sorted(by_dir):
    print(f"  {d}: {len(by_dir[d])}")
