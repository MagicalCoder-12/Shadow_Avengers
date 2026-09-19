import os, re

static_refs = set()
uid_refs = set()
gd_texts = {}
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'addons', '.fennara', 'android', 'Apks', '.qoder', '.vscode', '.freebuff')]
    for fn in files:
        p = os.path.join(root, fn).replace(os.sep, '/').lstrip('./')
        txt = open(os.path.join(root, fn), encoding='utf-8', errors='ignore').read()
        if fn.endswith(('.tscn', '.tres')):
            for m in re.finditer(r'path="(res://[^"]+)"', txt):
                static_refs.add(m.group(1))
            for m in re.finditer(r'uid="(uid://[a-z0-9]+)"', txt):
                uid_refs.add(m.group(1))
        elif fn.endswith('.gd'):
            gd_texts[p] = txt
            for m in re.finditer(r'(?:preload|load)\(["\']([^"\')]+)["\']\)', txt):
                static_refs.add(m.group(1))
            for m in re.finditer(r'"(uid://[a-z0-9]+)"', txt):
                uid_refs.add(m.group(1))

proj = open('project.godot', encoding='utf-8').read()
for m in re.finditer(r'autoload/\w+="\*?(res://[^"]+)"', proj):
    static_refs.add(m.group(1))

class_defs = {}
for p, txt in gd_texts.items():
    m = re.search(r'^class_name\s+(\w+)', txt, re.M)
    if m:
        class_defs[m.group(1)] = p

class_used = set()
for name, defp in class_defs.items():
    for p, txt in gd_texts.items():
        if p == defp:
            continue
        if re.search(r'\b' + name + r'\b', txt):
            class_used.add(defp)
            break

dyn_dirs = set()
for p, txt in gd_texts.items():
    for m in re.finditer(r'"res://([^"]*%[sd][^"]*)"', txt):
        dyn_dirs.add(m.group(1).split('/')[0] + '/')
print("dynamic template dirs:", sorted(dyn_dirs))

candidates = []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'addons', '.fennara', 'android', 'Apks', '.qoder', '.vscode', '.freebuff')]
    for fn in files:
        if not fn.endswith(('.gd', '.tscn', '.tres', '.gdshader')):
            continue
        p = os.path.join(root, fn).replace(os.sep, '/').lstrip('./')
        if ('res://' + p) in static_refs:
            continue
        if p in class_used:
            continue
        if any(p.startswith(d) for d in dyn_dirs):
            continue
        txt = open(p, encoding='utf-8', errors='ignore').read()
        mu = re.search(r'\[gd_scene[^\]]*uid="(uid://[a-z0-9]+)"', txt)
        if mu and mu.group(1) in uid_refs:
            continue
        mu2 = re.search(r'\[gd_resource[^\]]*uid="(uid://[a-z0-9]+)"', txt)
        if mu2 and mu2.group(1) in uid_refs:
            continue
        candidates.append(p)

print("ORPHAN CANDIDATES:", len(candidates))
for c in sorted(candidates):
    print(" ", c)
