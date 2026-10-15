"""Writes CRITTERWEIGHT UI icon SVG masters (64x64 viewBox) + DPITexture import stubs.

Usage: python make_icons.py <game/assets/ui dir>
UI icons are flat single-colour glyphs (#f2f2ec, dark cut lines #1a1d24) tinted at runtime.
Element icons bake their element colour with a light outline and a dark halo so they read on
any background and without colour (ELEMENTS.md shapes).
"""
import os
import sys

L = "#f2f2ec"   # glyph light
D = "#1a1d24"   # cut lines / halo

def svg(body, size=64):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 64 64">\n%s\n</svg>\n'
            % (size, size, body.strip()))

def stroke(d, w, color=L, cap="round"):
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="round"/>'
            % (d, color, w, cap))

def gear():
    teeth = "".join('<rect x="27.5" y="3" width="9" height="13" rx="2" transform="rotate(%d 32 32)"/>' % a
                    for a in range(0, 360, 45))
    return '<g fill="%s"><circle cx="32" cy="32" r="20"/>%s</g><circle cx="32" cy="32" r="7.5" fill="%s"/>' % (L, teeth, D)

def star_points(cx, cy, ro, ri):
    import math
    pts = []
    for k in range(10):
        a = math.radians(-90 + 36 * k)
        r = ro if k % 2 == 0 else ri
        pts.append("%.2f,%.2f" % (cx + r * math.cos(a), cy + r * math.sin(a)))
    return " ".join(pts)

UI = {
    # main menu
    "fight": '<g fill="%s"><rect x="13" y="23" width="38" height="31" rx="9"/><circle cx="19.5" cy="24" r="6.5"/>'
             '<circle cx="28.5" cy="21.5" r="7"/><circle cx="37.5" cy="21.5" r="7"/><circle cx="46" cy="24" r="6.5"/>'
             '<rect x="18" y="55" width="28" height="6" rx="2"/></g>'
             '<path d="M24 18 V33 M33 15 V33 M42 18 V33" stroke="%s" stroke-width="2.6" stroke-linecap="round"/>'
             '<rect x="8" y="34" width="27" height="11" rx="5.5" fill="%s" stroke="%s" stroke-width="2.6"/>' % (L, D, L, D),
    "campaign": '<g fill="%s"><rect x="3" y="25" width="58" height="14" rx="5"/><circle cx="32" cy="32" r="17"/></g>'
                '<circle cx="32" cy="32" r="11" fill="none" stroke="%s" stroke-width="3"/>'
                '<polygon points="%s" fill="%s"/>'
                '<rect x="7" y="29" width="5" height="6" rx="1" fill="%s"/><rect x="52" y="29" width="5" height="6" rx="1" fill="%s"/>'
                % (L, D, star_points(32, 32.5, 7.5, 3.2), D, D, D),
    "online": '<circle cx="32" cy="32" r="26" fill="%s"/><g fill="none" stroke="%s" stroke-width="3">'
              '<ellipse cx="32" cy="32" rx="11" ry="26"/><path d="M6 32 H58 M10 19 H54 M10 45 H54"/></g>' % (L, D),
    "tutorial": '<g fill="%s"><circle cx="25" cy="39" r="16"/><path d="M28 23 H56 a4 4 0 0 1 4 4 v7 a4 4 0 0 1 -4 4 H36 Z"/></g>'
                '<circle cx="25" cy="39" r="5.5" fill="%s"/>%s' % (L, D, stroke("M13 27 C 6 18 11 7 22 7", 3.5)),
    "create": '<path fill="%s" d="M45 5 a15 15 0 0 0 -13 21 L7 51 a5.5 5.5 0 0 0 7.8 7.8 L39.8 33.8 a15 15 0 0 0 21 -13 '
              'l-8.5 8.5 -9.4 -3 -3 -9.4 z"/>' % L,
    "lab": '<path fill="%s" d="M23 5 H41 V11 H37.5 V24 L55 52 a6 6 0 0 1 -5 9 H14 a6 6 0 0 1 -5 -9 L26.5 24 V11 H23 Z"/>'
           '<path fill="%s" opacity="0.45" d="M18 41 H46 L53.5 53 a3 3 0 0 1 -2.5 4.5 H13 a3 3 0 0 1 -2.5 -4.5 Z"/>'
           '<circle cx="29" cy="49" r="3" fill="%s"/><circle cx="37" cy="44" r="2.2" fill="%s"/>' % (L, D, D, D),
    "mods": '<path fill="%s" d="M10 18 H24 a6 6 0 1 1 12 0 H50 V32 a6 6 0 1 1 0 12 V58 H36 a6 6 0 1 0 -12 0 H10 V44 '
            'a6 6 0 1 0 0 -12 Z"/>' % L,
    "profile": '<g fill="%s"><circle cx="32" cy="21" r="13"/><path d="M7 59 C 7 43 18 36 32 36 C 46 36 57 43 57 59 Z"/></g>' % L,
    "settings": gear(),
    "credits": '<rect x="10" y="7" width="44" height="50" rx="7" fill="%s"/>%s' % (L, stroke("M19 19 H45 M19 28 H45 M19 37 H40 M19 46 H33", 3.6, D)),
    "quit": '<path fill="%s" d="M9 6 H37 V58 H9 Z"/><circle cx="31" cy="33" r="2.8" fill="%s"/>%s'
            % (L, D, stroke("M41 32 H58 M50 23 L59 32 L50 41", 5.5)),
    # generic
    "back": stroke("M41 9 L18 32 L41 55", 8),
    "forward": stroke("M23 9 L46 32 L23 55", 8),
    "lock": '<rect x="11" y="28" width="42" height="30" rx="6" fill="%s"/>%s'
            '<circle cx="32" cy="41" r="4.5" fill="%s"/><rect x="29.8" y="41" width="4.4" height="9" rx="1.5" fill="%s"/>'
            % (L, stroke("M20 29 V21 a12 12 0 0 1 24 0 V29", 6.5), D, D),
    "warning": '<path d="M32 6 L59 55 H5 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>'
               '<rect x="28.8" y="22" width="6.4" height="19" rx="2.5" fill="%s"/><circle cx="32" cy="48" r="3.8" fill="%s"/>'
               % (L, L, D, D),
    "check": stroke("M9 34 L26 51 L55 15", 9),
    "info": '<circle cx="32" cy="32" r="27" fill="%s"/><circle cx="32" cy="18.5" r="4.5" fill="%s"/>'
            '<rect x="28.3" y="27" width="7.4" height="23" rx="2.5" fill="%s"/>' % (L, D, D),
    "error": '<circle cx="32" cy="32" r="27" fill="%s"/>%s' % (L, stroke("M21 21 L43 43 M43 21 L21 43", 6.5, D)),
    "star": '<polygon points="%s" fill="%s" stroke="%s" stroke-width="3" stroke-linejoin="round"/>' % (star_points(32, 34, 28, 12), L, L),
    "random": '<rect x="7" y="7" width="50" height="50" rx="11" fill="%s"/><g fill="%s"><circle cx="20" cy="20" r="5"/>'
              '<circle cx="44" cy="20" r="5"/><circle cx="32" cy="32" r="5"/><circle cx="20" cy="44" r="5"/><circle cx="44" cy="44" r="5"/></g>' % (L, D),
    "gamepad": '<path fill="%s" d="M18 16 H46 C 57 16 62 30 62 42 C 62 53 55 57 49 52 L42 44 H22 L15 52 C 9 57 2 53 2 42 C 2 30 7 16 18 16 Z"/>'
               '<path fill="%s" d="M14 28 h5 v-5 h5 v5 h5 v5 h-5 v5 h-5 v-5 h-5 Z"/>'
               '<g fill="%s"><circle cx="45" cy="25" r="3.3"/><circle cx="52" cy="31" r="3.3"/><circle cx="38" cy="31" r="3.3"/><circle cx="45" cy="37" r="3.3"/></g>' % (L, D, D),
    "keyboard": '<rect x="3" y="15" width="58" height="35" rx="6" fill="%s"/><g fill="%s">' % (L, D)
                + "".join('<rect x="%d" y="21" width="7" height="6" rx="1.2"/>' % x for x in range(9, 56, 10))
                + "".join('<rect x="%d" y="30" width="7" height="6" rx="1.2"/>' % x for x in range(13, 52, 10))
                + '<rect x="17" y="39" width="30" height="6" rx="1.5"/></g>',
    "spectate": '<path fill="%s" d="M2 32 C 13 13 51 13 62 32 C 51 51 13 51 2 32 Z"/><circle cx="32" cy="32" r="12" fill="%s"/>'
                '<circle cx="32" cy="32" r="5" fill="%s"/>' % (L, D, L),
    "practice": '<circle cx="32" cy="32" r="27" fill="%s"/><circle cx="32" cy="32" r="19.5" fill="%s"/>'
                '<circle cx="32" cy="32" r="12.5" fill="%s"/><circle cx="32" cy="32" r="5.5" fill="%s"/>' % (L, D, L, D),
    "versus": stroke("M6 12 L27 32 L6 52", 7) + stroke("M58 12 L37 32 L58 52", 7)
              + '<polygon points="%s" fill="%s"/>' % (star_points(32, 32, 9, 3.8), L),
    "quick": '<circle cx="32" cy="37" r="23" fill="%s"/><rect x="26" y="4" width="12" height="7" rx="2" fill="%s"/>'
             '<rect x="29.5" y="9" width="5" height="6" fill="%s"/>%s' % (L, L, L, stroke("M32 37 L32 23 M32 37 L42 43", 4.5, D)),
    "bot": '<rect x="10" y="18" width="44" height="38" rx="9" fill="%s"/><circle cx="32" cy="9" r="5" fill="%s"/>'
           '<rect x="30" y="11" width="4" height="8" fill="%s"/><g fill="%s"><circle cx="23" cy="34" r="5.5"/><circle cx="41" cy="34" r="5.5"/>'
           '<rect x="22" y="44" width="20" height="4.5" rx="2"/></g>' % (L, L, L, D),
    "trophy": '<path fill="%s" d="M16 6 H48 V22 C 48 33 41 40 32 40 C 23 40 16 33 16 22 Z"/>%s'
              '<rect x="28.5" y="39" width="7" height="10" fill="%s"/><rect x="17" y="49" width="30" height="9" rx="2.5" fill="%s"/>'
              % (L, stroke("M16 12 H8 C 8 24 12 28 18 29 M48 12 H56 C 56 24 52 28 46 29", 4.5), L, L),
    "can": '<rect x="17" y="7" width="30" height="51" rx="7" fill="%s"/><rect x="17" y="22" width="30" height="20" fill="%s" opacity="0.4"/>'
           '<path d="M32 25 C 36 31 38 33 38 36 a6 6 0 0 1 -12 0 C 26 33 28 31 32 25 Z" fill="%s"/>'
           '<rect x="20" y="10" width="24" height="3" rx="1.5" fill="%s"/>' % (L, D, L, D),
    "restart": '%s<polygon points="40,9 52,19 37,25" fill="%s"/>' % (stroke("M50 33 A18 18 0 1 1 44 18.5", 7, L, "butt"), L),
    "plus": stroke("M32 10 V54 M10 32 H54", 9),
    "close": stroke("M14 14 L50 50 M50 14 L14 50", 8.5),
    "edit": '<path fill="%s" d="M42 7 L57 22 L24 55 L7 58 L10 41 Z"/>%s' % (L, stroke("M36 13 L51 28 M13 43 L21 51", 3, D)),
    "folder": '<path fill="%s" d="M4 15 a5 5 0 0 1 5 -5 H25 L31 17 H55 a5 5 0 0 1 5 5 V50 a5 5 0 0 1 -5 5 H9 a5 5 0 0 1 -5 -5 Z"/>'
              '<path fill="%s" opacity="0.35" d="M4 24 H60 V27 H4 Z"/>' % (L, D),
    "copy": '<rect x="20" y="20" width="36" height="38" rx="5" fill="%s"/><rect x="8" y="6" width="36" height="38" rx="5" fill="none" stroke="%s" stroke-width="5"/>' % (L, L),
    "arena": '<polygon points="22,4 42,4 60,22 60,42 42,60 22,60 4,42 4,22" fill="%s"/>'
             '<polygon points="24.5,11 39.5,11 53,24.5 53,39.5 39.5,53 24.5,53 11,39.5 11,24.5" fill="none" stroke="%s" stroke-width="3"/>'
             '<path d="M18 18 L46 46 M46 18 L18 46 M32 11 V53 M11 32 H53" stroke="%s" stroke-width="1.6" opacity="0.6"/>' % (L, D, D),
    "rules": '<rect x="10" y="9" width="44" height="51" rx="6" fill="%s"/><rect x="22" y="4" width="20" height="10" rx="3" fill="%s" stroke="%s" stroke-width="3"/>'
             '%s' % (L, L, D, stroke("M19 33 L27 41 L45 23", 5.5, D)),
    "team": '<g fill="%s"><circle cx="22" cy="21" r="10"/><circle cx="44" cy="25" r="8"/>'
            '<path d="M3 55 C 3 41 11 35 22 35 C 33 35 41 41 41 55 Z"/><path d="M38 37 C 50 36 61 41 61 54 H44 C 44 46 42 41 38 37 Z"/></g>' % L,
    "skull": '',  # placeholder removed below (not used: KO is a star burst, never a skull)
}
del UI["skull"]

# --- element icons: baked colour + light outline + dark halo ----------------------------------
FLAME = ("M32 4 C 36 14 46 20 49 31 C 52 41 47 54 35 58 C 23 61 13 53 13 42 C 13 33 18 27 22 21 "
         "C 23 28 26 31 29 30 C 27 21 28 12 32 4 Z")
FLAME_CORE = "M33 28 C 36 34 42 38 41 45 C 40 51 36 54 32 54 C 27 54 23 50 24 44 C 25 38 30 35 33 28 Z"
WAVE = ("M5 54 C 11 52 17 44 21 36 C 27 22 37 13 47 13 C 55 13 60 20 60 28 C 60 35 55 38 50 37 "
        "C 46 36 44 32 46 29 C 48 27 51 28 52 30 C 52 25 48 22 44 23 C 37 25 34 34 36 42 C 38 48 46 52 59 54 Z")
BOLT = "M39 3 L14 35 L29 35 L22 61 L51 27 L36 27 L43 3 Z"
BLOB_PARTS = [
    '<circle cx="32" cy="27" r="20"/>',
    '<path d="M15 33 C 15 42 17 47 17 51 a4.5 4.5 0 0 0 9 0 C 26 45 25 41 25 38 Z"/>',
    '<path d="M27.5 40 C 28 48 28 53 28 57 a4.5 4.5 0 0 0 9 0 C 37 52 36.5 47 37 40 Z"/>',
    '<path d="M40 38 C 40 41 39 44 39 47 a4 4 0 0 0 8 0 C 47 43 48 39 49 33 Z"/>',
]
HEX = "M5 32 L18 13 L46 13 L59 32 L46 51 L18 51 Z"
HEX_CRACK = "M27 13 L31 25 L24 32 L33 42 L30 51"
SWIRL = ("M37 29 C 37 25 43 25 43 30 C 43 36 35 38 31 34 C 26 29 30 20 38 19 C 48 18 55 27 52 36 "
         "C 49 45 40 49 30 47 L6 47")
SWIRL_TAILS = "M24 38 L9 38 M38 55 L14 55"

def element_icon(parts_paths, fill, extra="", outline=L, halo_w=11, line_w=6):
    """parts_paths: list of SVG shape elements (without fill/stroke attributes)."""
    halo = "".join(p.replace("/>", ' fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (D, halo_w))
                   for p in parts_paths)
    line = "".join(p.replace("/>", ' fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (outline, line_w))
                   for p in parts_paths)
    body = "".join(p.replace("/>", ' fill="%s"/>' % fill) for p in parts_paths)
    return halo + line + body + extra

ELEMENTS = {
    "el_scorch": '<g transform="rotate(10 32 34)">%s</g>' % element_icon(['<path d="%s"/>' % FLAME], "#ff6b2b",
                 '<path d="%s" fill="#ffd9a0"/>' % FLAME_CORE),
    "el_brine": element_icon(['<path d="%s"/>' % WAVE], "#2e9be0"),
    "el_static": element_icon(['<path d="%s"/>' % BOLT], "#f7e04a"),
    "el_sludge": element_icon(BLOB_PARTS, "#8bd426",
                 '<circle cx="25" cy="21" r="4" fill="#c7e66b"/><circle cx="38" cy="30" r="2.6" fill="#c7e66b"/>'),
    "el_grit": element_icon(['<path d="%s"/>' % HEX], "#b8905e",
               '<path d="%s" fill="none" stroke="%s" stroke-width="3.2" stroke-linejoin="round" stroke-linecap="round"/>' % (HEX_CRACK, D)),
    "el_gale": (stroke(SWIRL + " " + SWIRL_TAILS, 13, D) + stroke(SWIRL + " " + SWIRL_TAILS, 9, "#4fb3b8")
                + stroke(SWIRL + " " + SWIRL_TAILS, 4.2, "#cff4f2")),
}

LOGO = """
<polygon points="40,4 88,4 124,40 124,88 88,124 40,124 4,88 4,40" fill="#1a1d24" stroke="#c9a227" stroke-width="6" stroke-linejoin="round"/>
<polygon points="44,16 84,16 112,44 112,84 84,112 44,112 16,84 16,44" fill="#232731" stroke="#5b6168" stroke-width="3"/>
<g stroke="#5b6168" stroke-width="1.6" opacity="0.7">
<path d="M16 44 L84 112 M30 30 L98 98 M44 16 L112 84 M16 84 L84 16 M30 98 L98 30 M44 112 L112 44"/>
</g>
<g transform="rotate(-14 64 64)">
<rect x="46" y="26" width="36" height="72" rx="9" fill="#8bd426" stroke="#1a1d24" stroke-width="4"/>
<rect x="46" y="48" width="36" height="24" fill="#5c8f17"/>
<rect x="51" y="31" width="26" height="4" rx="2" fill="#1a1d24"/>
<path d="M64 51 C 69 58 71 61 71 64 a7 7 0 0 1 -14 0 C 57 61 59 58 64 51 Z" fill="#f2f2ec"/>
</g>
<g transform="rotate(32 64 64)">
<rect x="22" y="56" width="62" height="20" rx="8" fill="#f2f2ec" stroke="#1a1d24" stroke-width="4"/>
<g fill="#f2f2ec" stroke="#1a1d24" stroke-width="3.5">
<rect x="78" y="48" width="18" height="36" rx="8"/>
</g>
<path d="M85 55 V77" stroke="#1a1d24" stroke-width="2.5"/>
</g>
"""

def logo_svg(size):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 128 128">\n%s\n</svg>\n'
            % (size, size, LOGO.strip()))

IMPORT_STUB = '[remap]\n\nimporter="svg"\ntype="DPITexture"\n'

def write(path, text, stub=True):
    with open(path, "w", newline="\n", encoding="utf-8") as f:
        f.write(text)
    imp = path + ".import"
    if stub and not os.path.exists(imp):
        with open(imp, "w", newline="\n", encoding="utf-8") as f:
            f.write(IMPORT_STUB)

def main():
    ui_dir = sys.argv[1]
    icons = os.path.join(ui_dir, "icons")
    os.makedirs(icons, exist_ok=True)
    for name, body in UI.items():
        write(os.path.join(icons, name + ".svg"), svg(body))
    for name, body in ELEMENTS.items():
        write(os.path.join(icons, name + ".svg"), svg(body))
    write(os.path.join(ui_dir, "logo_mark.svg"), logo_svg(128))
    print("wrote %d ui icons, %d element icons, logo" % (len(UI), len(ELEMENTS)))

if __name__ == "__main__":
    main()
