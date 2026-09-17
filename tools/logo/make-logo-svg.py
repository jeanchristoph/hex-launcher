"""Génère tools/logo/hex-launcher-logo.svg : cadre or + monogramme HL + gemme, fond transparent (le drapeau se compose
derrière, voir tools/make-flag-icons.ps1). Silhouette des lettres vectorisée par potrace depuis le dessin de référence
tools/logo/hex-launcher-logo-drawing.png ; tout le reste (cadre, biseaux, gemme, écrous) est géométrique.
Matière commune : liseré bleu nuit, chanfrein or sombre côté ombre, éclat blanc côté lumière (haut, légèrement gauche), face or.

Dépendances (outil de développement, hors release) : Python 3, Pillow, numpy ; potrace et resvg dans le PATH
(`scoop install potrace resvg`).

Usage : python tools/logo/make-logo-svg.py [--preview DOSSIER]
  --preview  écrit aussi des PNG de contrôle (512 px, 48 et 32 px sur drapeau FR, planche comparative) dans DOSSIER.
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, subprocess, re, argparse, tempfile, os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'tools' / 'logo' / 'hex-launcher-logo-drawing.png'
OUT = ROOT / 'tools' / 'logo' / 'hex-launcher-logo.svg'
args = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
args.add_argument('--preview', metavar='DOSSIER', help='dossier des PNG de contrôle (aucun par défaut)')
options = args.parse_args()
WORK = tempfile.mkdtemp(prefix='hex-launcher-logo-')

PALETTE = {'face': (253, 201, 46), 'chamfer': (217, 150, 15), 'dark': (1, 5, 18), 'gem': (1, 133, 253), 'stud': (163, 114, 16)}
GOLD, CHAMFER, DARK, GEM, STUD = '#FDC92E', '#D9960F', '#010512', '#0185FD', '#D9960F'
SIZE, MARGIN, RADIUS, THICK = 256, 7, 40, 13
LOGO_REGION = (46, 150, 466, 466)          # zone du logo dans l'image 512 (hors cadre)

im = np.array(Image.open(SRC).convert('RGBA')).astype(int)
H, W = im.shape[:2]
rgb, alpha = im[:, :, :3], im[:, :, 3]
names = list(PALETTE)
dist = np.stack([((rgb - np.array(c)) ** 2).sum(axis=2) for c in PALETTE.values()], axis=2)
cls = dist.argmin(axis=2)
opaque = alpha > 128
# Zone intérieure du cadre (carré arrondi, en retrait de quelques px) : rien du cadre n'entre dans les masques du logo
_inset, _radius = (MARGIN + THICK) * 2 + 4, (RADIUS - THICK) * 2 - 4
_region_img = Image.new('L', (W, H), 0)
ImageDraw.Draw(_region_img).rounded_rectangle((_inset, _inset, W - _inset, H - _inset), radius=_radius, fill=255)
region = np.array(_region_img) > 0; region[:LOGO_REGION[1], :] = False
def is_class(*ns): return opaque & region & np.isin(cls, [names.index(n) for n in ns])

def clean(mask, r=1):
    img = Image.fromarray((mask * 255).astype(np.uint8))
    k = 2 * r + 1
    img = img.filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.MinFilter(k))   # fermeture
    img = img.filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k))   # ouverture
    return np.array(img) > 0

def trace(mask, name, turd=40, alphamax=1.0):
    pbm = f'{WORK}/{name}.pbm'; svg = f'{WORK}/{name}.svg'
    Image.fromarray(((~mask) * 255).astype(np.uint8)).convert('1').save(pbm)
    subprocess.run(['potrace', '-s', '-t', str(turd), '-a', str(alphamax), '-O', '0.2', '-o', svg, pbm], check=True)
    text = open(svg, encoding='utf-8').read()
    return ' '.join(' '.join(d.split()) for d in re.findall(r'<path d="([^"]+)"', text))


def circle_from(mask):
    ys, xs = np.where(mask)
    if len(xs) == 0: return None
    d = max(xs.max() - xs.min(), ys.max() - ys.min()) + 1
    return ((xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2, d / 2)

silhouette = clean(is_class('face', 'chamfer', 'dark', 'gem', 'stud'))
inner      = clean(is_class('face', 'chamfer', 'gem', 'stud'))
face       = clean(is_class('face', 'gem', 'stud'))
gem        = circle_from(is_class('gem'))
yy, xx = np.mgrid[0:H, 0:W]
near_gem = ((xx - gem[0]) ** 2 + (yy - gem[1]) ** 2) ** 0.5
stud_mask  = is_class('chamfer') & (near_gem > gem[2] + 2) & (near_gem < gem[2] + 45)   # les clous sont de la couleur du chanfrein
# clous : la plus grosse composante connexe de la classe « clou » de chaque côté de la gemme
def components(mask):
    seen = np.zeros_like(mask); comps = []
    for y0, x0 in zip(*np.where(mask)):
        if seen[y0, x0]: continue
        stack = [(y0, x0)]; seen[y0, x0] = True; pts = []
        while stack:
            y, x = stack.pop(); pts.append((y, x))
            for ny, nx in ((y+1,x),(y-1,x),(y,x+1),(y,x-1)):
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; stack.append((ny, nx))
        comps.append(pts)
    return comps
studs = []
for side in ('left', 'right'):
    m = stud_mask.copy()
    if side == 'left': m[:, int(gem[0]):] = False
    else: m[:, :int(gem[0])] = False
    def is_disc(c):
        ys, xs = zip(*c); w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        return 8 <= w <= 24 and abs(w - h) <= 3 and len(c) / (w * h) > 0.6
    comps = [c for c in components(m) if is_disc(c)]
    if not comps: continue
    pts = max(comps, key=len)
    ys, xs = zip(*pts)
    studs.append(((min(xs) + max(xs) + 1) / 2, (min(ys) + max(ys) + 1) / 2, (max(max(xs) - min(xs), max(ys) - min(ys)) + 1) / 2))

silhouette_d = trace(silhouette, 'outline')
OUTLINE_W, CHAMFER_W = 2.4, 6.0     # contour, et retrait de base de la face (px à 256) ; le chanfrein visible dépend du côté
# Biseaux lus sur la source : chanfrein visible = CHAMFER_W - décalage - éclat côté lumière (3,5 px à gauche et en haut),
# CHAMFER_W + décalage côté ombre (6,5 px à droite, 6 px en dessous) ; éclat blanc entre chanfrein et face côté lumière
BEVEL_DX, BEVEL_DY = 0.5, 0.0       # décalage de la face vers la lumière (gauche, haut)
SHINE_W, SHINE_H = 2.0, 2.5         # éclat blanc sur les flancs gauches et les arêtes hautes
UNIT = 20                            # 1 px à 256 = 2 px à 512 = 20 unités potrace

def erode(mask, radius_px):
    """Érosion quasi circulaire : alternance de voisinages 4 et 8 (octogone)."""
    m = mask.copy()
    for k in range(int(round(radius_px))):
        up, down = np.roll(m, -1, 0), np.roll(m, 1, 0); left, right = np.roll(m, -1, 1), np.roll(m, 1, 1)
        n = m & up & down & left & right
        if k % 2: n &= np.roll(up, -1, 1) & np.roll(up, 1, 1) & np.roll(down, -1, 1) & np.roll(down, 1, 1)
        m = n
    return m

face_d = trace(erode(silhouette, (OUTLINE_W + CHAMFER_W) * 2), 'face', turd=20)
inner_d = trace(erode(silhouette, (OUTLINE_W + 0.5) * 2), 'inner', turd=20)   # tout l'intérieur du contour : borne des copies décalées

# Espace 512 (potrace : translate(0,512) scale(0.1,-0.1)) → espace icône 256
def f(v): return f'{v:.2f}'
# Cadre : anneau en relief, même matière que le logo — liserés sombres, chanfrein, éclat blanc côté lumière, face or.
# Les copies décalées vers le haut-gauche font le biseau : chanfrein fin/éclat sur le bord extérieur haut-gauche
# et sur le bord intérieur bas-droit ; chanfrein large sur le bord extérieur bas-droit et le bord intérieur haut-gauche.
FRAME_OUTLINE_OUT, FRAME_OUTLINE_IN = 1.0, 1.5     # liserés sombres extérieur / intérieur
FRAME_BAND = 3.0                                   # retrait de base de la face
FRAME_DX, FRAME_DY = 1.0, 1.0                      # décalage de la face vers la lumière
FRAME_SHINE_W, FRAME_SHINE_H = 1.5, 1.5            # éclat blanc

def rounded_square(inset):
    """Carré arrondi à `inset` px du bord du cadre (marge comprise), sens horaire."""
    x0 = MARGIN + inset; x1 = SIZE - MARGIN - inset; r = max(0.0, RADIUS - inset)
    return (f'M {f(x0 + r)} {f(x0)} L {f(x1 - r)} {f(x0)} A {f(r)} {f(r)} 0 0 1 {f(x1)} {f(x0 + r)} '
            f'L {f(x1)} {f(x1 - r)} A {f(r)} {f(r)} 0 0 1 {f(x1 - r)} {f(x1)} '
            f'L {f(x0 + r)} {f(x1)} A {f(r)} {f(r)} 0 0 1 {f(x0)} {f(x1 - r)} '
            f'L {f(x0)} {f(x0 + r)} A {f(r)} {f(r)} 0 0 1 {f(x0 + r)} {f(x0)} Z')

def ring(inset_outer, inset_inner):
    return rounded_square(inset_outer) + ' ' + rounded_square(inset_inner)

def frame_svg():
    band_out, band_in = FRAME_OUTLINE_OUT + FRAME_BAND, THICK - FRAME_OUTLINE_IN - FRAME_BAND
    face = ring(band_out, band_in)
    return f'''  <defs>
    <clipPath id="frame-clip"><path d="{ring(FRAME_OUTLINE_OUT, THICK - FRAME_OUTLINE_IN)}" fill-rule="evenodd" clip-rule="evenodd"/></clipPath>
    <path id="frame-face" d="{face}" fill-rule="evenodd"/>
  </defs>
  <g id="frame">
    <path d="{ring(0, THICK)}" fill="{DARK}" fill-rule="evenodd"/>
    <g clip-path="url(#frame-clip)">
      <path d="{ring(FRAME_OUTLINE_OUT, THICK - FRAME_OUTLINE_IN)}" fill="{CHAMFER}" fill-rule="evenodd"/>
      <use href="#frame-face" fill="#FFFFFF" fill-opacity="0.9" transform="translate({f(-(FRAME_DX + FRAME_SHINE_W))},{f(-(FRAME_DY + FRAME_SHINE_H))})"/>
      <use href="#frame-face" fill="{GOLD}" transform="translate({f(-FRAME_DX)},{f(-FRAME_DY)})"/>
    </g>
  </g>'''


gx, gy, gr = gem[0] / 2, gem[1] / 2, gem[2] / 2
BEZEL_IN, BEZEL_W = 1.6, 1.8   # contour noir contre la gemme, largeur de l'anneau de métal (px à 256)

# Gemme taillée (modèle) : table hexagonale à sommets latéraux (arêtes haut et bas horizontales), six facettes autour.
# Lumière à -105° (15° à gauche de la verticale) : facette la plus exposée presque blanche, facettes basses ombrées.
import math
def hexagon(cx, cy, radius, rotation=0):
    return [(cx + radius * math.cos(math.radians(rotation + 60 * k)), cy + radius * math.sin(math.radians(rotation + 60 * k))) for k in range(6)]
def poly(points, fill, opacity):
    pts = ' '.join(f'{f(x)},{f(y)}' for x, y in points)
    return f'    <polygon points="{pts}" fill="{fill}" fill-opacity="{opacity:.2f}"/>'
outer, table = hexagon(gx, gy, gr * 0.97), hexagon(gx, gy, gr * 0.52)
facet_lines = []
for k in range(6):
    a, b = outer[k], outer[(k + 1) % 6]; c, d = table[(k + 1) % 6], table[k]
    angle = math.atan2((a[1] + b[1]) / 2 - gy, (a[0] + b[0]) / 2 - gx)     # direction de la facette (-90° = haut)
    LIGHT = math.radians(-105)                                                # lumière haut-gauche, comme les biseaux des lettres
    dot = math.cos(angle - LIGHT)
    light, shade = max(0.0, dot) ** 0.5, max(0.0, -dot) ** 0.5
    if dot > 0.9: facet_lines.append(poly([a, b, c, d], '#FFFFFF', 0.88))             # facette face à la lumière : presque blanche
    elif light > 0: facet_lines.append(poly([a, b, c, d], '#FFFFFF', 0.10 + 0.45 * light))
    elif shade > 0: facet_lines.append(poly([a, b, c, d], DARK, 0.08 + 0.30 * shade))
    else: facet_lines.append(poly([a, b, c, d], '#FFFFFF', 0.10))
facet_lines.append(poly(table, '#FFFFFF', 0.28))
# Éclat : bande le long de l'arête haut-gauche de la table (entre les sommets à 180° et 240°)
t0, t1 = table[3], table[4]
inward = (gx - (t0[0] + t1[0]) / 2, gy - (t0[1] + t1[1]) / 2); k = 0.32
glint = [t0, t1, (t1[0] + inward[0] * k, t1[1] + inward[1] * k), (t0[0] + inward[0] * k, t0[1] + inward[1] * k)]
facet_lines.append(poly(glint, '#FFFFFF', 0.85))
facets_svg = chr(10).join(facet_lines)
# Écrous (espace 512, dans le groupe scale 0.5) : ombre portée or sombre décalée en bas-droite, dôme or, éclat blanc haut-gauche
STUD_SCALE = 0.85   # un peu plus petits que sur le dessin
def stud_svg_for(x, y, r):
    r = r * STUD_SCALE
    recess = f'    <circle cx="{f(x + r * 0.09)}" cy="{f(y + r * 0.34)}" r="{f(r * 1.2)}" fill="{CHAMFER}"/>'   # ombre portée sous l'écrou seulement, rien au-dessus
    base   = f'    <circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{CHAMFER}"/>'
    light  = f'    <circle cx="{f(x - r * 0.05)}" cy="{f(y - r * 0.2)}" r="{f(r * 0.75)}" fill="{GOLD}"/>'
    shine  = f'    <ellipse cx="{f(x - r * 0.12)}" cy="{f(y - r * 0.45)}" rx="{f(r * 0.5)}" ry="{f(r * 0.24)}" fill="#FFFFFF"/>'
    return chr(10).join((recess, base, light, shine))
stud_svg = '\n'.join(stud_svg_for(x, y, r) for x, y, r in studs)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <!-- hex-launcher : cadre or plat + monogramme HL vectorisé depuis l'illustration de référence + gemme. Fond transparent. -->
{frame_svg()}
  <defs>
    <path id="silhouette" d="{silhouette_d}"/>
    <clipPath id="inside"><use href="#silhouette"/></clipPath>
    <path id="face" d="{face_d}"/>
    <clipPath id="inner-clip"><path d="{inner_d}"/></clipPath>
  </defs>
  <g id="logo" transform="scale(0.5)">
    <!-- Silhouette du dessin, remplie chanfrein ; contour = trait épais découpé à la silhouette (moitié intérieure visible) -->
    <g transform="translate(0,{H}) scale(0.1,-0.1)" clip-path="url(#inside)">
      <use href="#silhouette" fill="{CHAMFER}"/>
      <use href="#silhouette" fill="none" stroke="{DARK}" stroke-width="{f(2 * OUTLINE_W * UNIT)}" stroke-linejoin="round"/>
      <!-- Biseau : face érodée, copie blanche décalée vers la lumière sous la copie or → éclat sur les flancs gauches et arêtes hautes -->
      <g clip-path="url(#inner-clip)">
        <use href="#face" fill="#FFFFFF" fill-opacity="0.9" transform="translate({f(-(BEVEL_DX + SHINE_W) * UNIT)},{f((BEVEL_DY + SHINE_H) * UNIT)})"/>
        <use href="#face" fill="{GOLD}" transform="translate({f(-BEVEL_DX * UNIT)},{f(BEVEL_DY * UNIT)})"/>
      </g>
    </g>
{stud_svg}
  </g>
  <g id="gem">
    <!-- Sertissage : anneau de métal en relief, blanc et or sombre seulement — ombre portée légère en dessous, chanfrein fin bas-droit, éclat haut-gauche ; contour noir contre la pierre -->
    <circle cx="{f(gx + 0.3)}" cy="{f(gy + 0.6)}" r="{f(gr + BEZEL_IN + BEZEL_W + 0.8)}" fill="{CHAMFER}"/>
    <circle cx="{f(gx)}" cy="{f(gy)}" r="{f(gr + BEZEL_IN + BEZEL_W)}" fill="{CHAMFER}"/>
    <circle cx="{f(gx - 0.6)}" cy="{f(gy - 0.6)}" r="{f(gr + BEZEL_IN + BEZEL_W - 0.7)}" fill="#FFFFFF"/>
    <circle cx="{f(gx - 0.15)}" cy="{f(gy - 0.15)}" r="{f(gr + BEZEL_IN + BEZEL_W - 0.6)}" fill="{GOLD}"/>
    <circle cx="{f(gx)}" cy="{f(gy)}" r="{f(gr + BEZEL_IN)}" fill="{DARK}"/>
    <circle cx="{f(gx)}" cy="{f(gy)}" r="{f(gr)}" fill="{GEM}"/>
{facets_svg}
  </g>
</svg>
'''
open(OUT, 'w', encoding='utf-8').write(svg)
print(f'OK : {OUT}')

# ---------------------------------------------------------------- Aperçus de contrôle (optionnels)
if options.preview:
    out_dir = Path(options.preview); out_dir.mkdir(parents=True, exist_ok=True)
    for size in (512, 48, 32):
        subprocess.run(['resvg', '-w', str(size), str(OUT), str(out_dir / f'hex-launcher-logo-{size}.png')], check=True)
    user = Image.open(SRC).convert('RGBA')
    svg_img = Image.open(out_dir / 'hex-launcher-logo-512.png').convert('RGBA')
    over = user.copy(); tint = svg_img.copy(); tint.putalpha(tint.split()[3].point(lambda a: int(a * 0.55))); over.alpha_composite(tint)
    def on_bg(img):
        bg = Image.new('RGBA', (512, 512), (40, 40, 46, 255)); bg.alpha_composite(img); return bg
    def on_flag(size, zoom):
        flag = Image.new('RGBA', (size, size), (0, 0, 0, 0)); d = ImageDraw.Draw(flag); t = size / 256
        d.rectangle((20*t, 20*t, 92*t, 236*t), fill=(0, 37, 153)); d.rectangle((92*t, 20*t, 164*t, 236*t), fill=(254, 254, 254)); d.rectangle((164*t, 20*t, 236*t, 236*t), fill=(235, 41, 58))
        flag.alpha_composite(Image.open(out_dir / f'hex-launcher-logo-{size}.png').convert('RGBA'))
        return flag.resize((size * zoom, size * zoom), Image.NEAREST)
    small = Image.new('RGBA', (512, 512), (40, 40, 46, 255))
    small.alpha_composite(on_flag(48, 1), (20, 20)); small.alpha_composite(on_flag(32, 1), (90, 28))
    small.alpha_composite(on_flag(48, 5), (20, 100)); small.alpha_composite(on_flag(32, 5), (300, 120))
    sheet = Image.new('RGB', (2048, 512))
    for i, img in enumerate((on_bg(user), on_bg(svg_img), on_bg(over), small)): sheet.paste(img.convert('RGB'), (512 * i, 0))
    sheet.save(out_dir / 'hex-launcher-logo-sheet.png')
    print(f'Aperçus : {out_dir}')
