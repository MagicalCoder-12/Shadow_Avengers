import os, re, sys

# device: 1080x2400 @ 480dpi (3x density). Stretch canvas_items+expand.
# scale = max(1080/1440, 2400/3200) = 0.75 -> 1 design px = 0.75 physical px = 0.25 dp
DP_PER_DESIGN_PX = 0.75 / 3.0
FONT_DP_MIN = 12.0          # readable minimum on mobile
TOUCH_DP_MIN = 48.0         # Material minimum touch target
FONT_MIN_DESIGN = FONT_DP_MIN / DP_PER_DESIGN_PX     # 48
TOUCH_MIN_DESIGN = TOUCH_DP_MIN / DP_PER_DESIGN_PX   # 192

TARGETS = [
    "MainScenes/start_menu.tscn", "MainScenes/Intern_Menu.tscn",
    "MainScenes/upgrade_menu.tscn", "MainScenes/Shop.tscn",
    "MainScenes/pause_menu.tscn", "MainScenes/game_over_screen.tscn",
    "MainScenes/level_completed.tscn", "MainScenes/difficulty_selection.tscn",
    "MainScenes/boss_clear.tscn", "Map/map.tscn", "HUD/HUD.tscn",
]

def parse_scene(path):
    lines = open(path, encoding='utf-8', errors='ignore').read().splitlines()
    subres = {}  # id -> {font_size}
    cur_sub = None
    for ln in lines:
        m = re.match(r'\[sub_resource type="LabelSettings" id="([^"]+)"', ln)
        if m:
            cur_sub = m.group(1); subres[cur_sub] = {}
            continue
        if cur_sub and ln.startswith('font_size'):
            subres[cur_sub]['font_size'] = int(re.search(r'=\s*(\d+)', ln).group(1))
        if cur_sub and (ln.startswith('[') and 'sub_resource' not in ln):
            cur_sub = None

    nodes = []
    cur = None
    for ln in lines:
        m = re.match(r'\[node name="([^"]+)"(?: type="([^"]+)")?(?: parent="([^"]+)")?', ln)
        if m:
            cur = {'name': m.group(1), 'type': m.group(2) or '(instance)', 'parent': m.group(3) or '',
                   'props': {}}
            nodes.append(cur)
            continue
        if cur is not None and '=' in ln and not ln.startswith('['):
            km = re.match(r'([\w/]+)\s*=\s*(.*)', ln.strip())
            if km:
                cur['props'][km.group(1)] = km.group(2).strip('"')
    return subres, nodes

def audit(path):
    if not os.path.exists(path):
        return
    subres, nodes = parse_scene(path)
    findings = []
    for n in nodes:
        t = n['type']
        props = n['props']
        # font size resolution
        fs = None
        if 'theme_override_font_sizes/font_size' in props:
            fs = int(props['theme_override_font_sizes/font_size'])
        elif 'label_settings' in props:
            sid = props['label_settings'].replace('SubResource(', '').strip('"')
            fs = subres.get(sid, {}).get('font_size')
        label_text = props.get('text', '')
        if fs is not None and t in ('Label', 'Button', 'TextureButton', 'LineEdit'):
            dp = fs * DP_PER_DESIGN_PX
            if dp < FONT_DP_MIN:
                findings.append((n['name'], t, f"font {fs}des={dp:.0f}dp", label_text[:24]))
        # control rect size (only when explicitly offset-positioned)
        if t in ('Button', 'TextureButton', 'BaseButton') or (t in ('Control', 'Panel') and 'custom_minimum_size' in props):
            try:
                l = float(props.get('offset_left', 0)); r = float(props.get('offset_right', 0))
                tp = float(props.get('offset_top', 0)); b = float(props.get('offset_bottom', 0))
                w = (r - l) * DP_PER_DESIGN_PX; h = (b - tp) * DP_PER_DESIGN_PX
                if w > 0 and h > 0 and min(w, h) < TOUCH_DP_MIN:
                    findings.append((n['name'], t, f"touch {w:.0f}x{h:.0f}dp", ''))
            except ValueError:
                pass
    if findings:
        print(f"\n=== {path} — {len(findings)} small elements")
        for f in findings:
            print(f"  {f[0]} [{f[1]}]: {f[2]} {('\"' + f[3] + '\"') if f[3] else ''}")
    else:
        print(f"\n=== {path} — OK")
    return len(findings)

total = 0
for t in TARGETS:
    total += audit(t) or 0
print(f"\nTOTAL small-element findings: {total}")
print(f"(conversion: 1 design px = {DP_PER_DESIGN_PX:.3f} dp on this device)")
