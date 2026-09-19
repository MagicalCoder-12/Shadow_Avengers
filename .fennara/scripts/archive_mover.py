import os, shutil

ARCHIVE = '_archive/orphan_assets'
moved = 0
skipped = 0

with open('.fennara/state/orphan_assets.txt') as f:
    orphans = [l.strip() for l in f if l.strip()]

WHITELIST = {'icon.png'}

for p in orphans:
    if p in WHITELIST or p.endswith('.import'):
        skipped += 1
        continue
    if not os.path.exists(p):
        skipped += 1
        continue
    dest = os.path.join(ARCHIVE, p)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.move(p, dest)
    moved += 1
    # move the .import file too, so re-import doesn't resurrect cache entries
    imp = p + '.import'
    if os.path.exists(imp):
        dest_imp = os.path.join(ARCHIVE, imp)
        os.makedirs(os.path.dirname(dest_imp), exist_ok=True)
        shutil.move(imp, dest_imp)
    # some .import sidecars have .uid files as well
    uid = p + '.uid'
    if os.path.exists(uid):
        dest_uid = os.path.join(ARCHIVE, uid)
        os.makedirs(os.path.dirname(dest_uid), exist_ok=True)
        shutil.move(uid, dest_uid)

print(f"moved: {moved}, skipped: {skipped}")
print("archive location:", os.path.abspath(ARCHIVE))
