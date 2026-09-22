"""Route ungated debug prints through DebugFlags.debug_print.

Debug prints that are already behind a `GameManager.debug_mode` guard are left
alone (that flag is itself hard-gated by DebugFlags). Everything else would spam
a release build's log, so it moves behind the build-type gate.

Usage: python .fennara/scripts/gate_prints.py [--dry-run]
"""
import io, os, re, sys

ROOTS = ['Autoloads', 'MainScenes', 'Levels', 'UI', 'Ships', 'Enemy', 'Bullet',
         'Map', 'Bosses', 'Pickups', 'Powerups', 'Coins', 'Assets']
SKIP = ('Autoloads/Scripts/Debug', 'addons', '_archive', '.fennara')
PRINT_RE = re.compile(r'^(\s*)print\((?P<args>.*)$')
GUARD_RE = re.compile(r'debug_mode|DebugFlags')

dry = '--dry-run' in sys.argv


def top_level_commas(args):
    depth = 0
    in_str = False
    quote = ''
    for ch in args:
        if in_str:
            if ch == quote:
                in_str = False
        elif ch in '"\'':
            in_str = True
            quote = ch
        elif ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        elif ch == ',' and depth == 0:
            return True
    return False


files, changed, total, multi = [], [], 0, []

for root in ROOTS:
    if not os.path.isdir(root):
        continue
    for dirpath, _dirnames, filenames in os.walk(root):
        posix = dirpath.replace(os.sep, '/')
        if any(s in posix for s in SKIP):
            continue
        for name in filenames:
            if name.endswith('.gd'):
                files.append(os.path.join(dirpath, name).replace(os.sep, '/'))

for path in files:
    with io.open(path, 'r', encoding='utf-8', newline='') as handle:
        lines = handle.read().split('\n')
    out = list(lines)
    hits = 0
    for index, line in enumerate(lines):
        match = PRINT_RE.match(line)
        if not match:
            continue
        context = '\n'.join(lines[max(0, index - 10):index])
        if GUARD_RE.search(context):
            continue  # already behind the debug_mode gate
        if top_level_commas(match.group('args')):
            multi.append('%s:%d  %s' % (path, index + 1, line.strip()))
            continue
        out[index] = '%sDebugFlags.debug_print(%s' % (match.group(1), match.group('args'))
        hits += 1
    if hits:
        total += hits
        changed.append((path, hits))
        if not dry:
            with io.open(path, 'w', encoding='utf-8', newline='') as handle:
                handle.write('\n'.join(out))

print('%s: %d ungated prints in %d files' % ('DRY RUN' if dry else 'APPLIED', total, len(changed)))
for path, hits in sorted(changed, key=lambda item: -item[1]):
    print('%4d  %s' % (hits, path))
if multi:
    print('\nMULTI-ARG (needs manual conversion, left untouched):')
    for entry in multi:
        print('   ' + entry)
